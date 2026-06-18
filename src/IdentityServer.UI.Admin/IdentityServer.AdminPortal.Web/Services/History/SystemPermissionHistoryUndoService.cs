using IdentityServer.Abstraction.DTO.History;
using IdentityServer.Abstraction.DTO.SystemPermissions;
using IdentityServer.Abstraction.Enums;

namespace IdentityServer.AdminPortal.Web.Services.History;

/// <summary>
/// Handles undo operations for SystemPermission and SystemPermission child entity history entries.
/// </summary>
public class SystemPermissionHistoryUndoService : EntityHistoryUndoServiceBase, IEntityHistoryUndoService<SystemPermissionDtoRead>
{
    private readonly IAdminApiService _adminApiService;

    private static readonly HashSet<string> _systemPermissionEntityTypes = new(StringComparer.OrdinalIgnoreCase)
    {
        HistoryEntryDtoExtensions.KnownEntityTypes.SystemPermission,
        HistoryEntryDtoExtensions.KnownEntityTypes.SystemPermissionEnvironment,
        HistoryEntryDtoExtensions.KnownEntityTypes.SystemPermissionRole
    };

    public SystemPermissionHistoryUndoService(IAdminApiService adminApiService)
    {
        _adminApiService = adminApiService;
    }

    /// <inheritdoc />
    public IReadOnlySet<string> SupportedEntityTypes => _systemPermissionEntityTypes;

    /// <inheritdoc />
    public bool CanHandle(string entityType) => _systemPermissionEntityTypes.Contains(entityType);

    /// <inheritdoc />
    public UndoEligibility CanUndo(HistoryEntryDto entry, SystemPermissionDtoRead? currentEntity)
    {
        var baseEligibility = CheckBaseEligibility(entry);
        if (!baseEligibility.CanUndo)
        {
            return baseEligibility;
        }

        if (currentEntity == null)
        {
            return UndoEligibility.Ineligible("Parent entity not loaded.");
        }

        return CheckConflicts(entry, currentEntity);
    }

    /// <inheritdoc />
    public async Task<ApiCallResult<SystemPermissionDtoRead>> ExecuteUndoAsync(HistoryEntryDto entry, SystemPermissionDtoRead entity)
    {
        return entry.EventType switch
        {
            HistoryEventType.Updated => await ExecuteUndoUpdateAsync(entry, entity.Id),
            HistoryEventType.Deleted => await ExecuteUndoDeleteAsync(entry, entity),
            _ => ApiCallResult<SystemPermissionDtoRead>.Error($"Unsupported event type {entry.EventType} for undo.")
        };
    }

    private static UndoEligibility CheckConflicts(HistoryEntryDto entry, SystemPermissionDtoRead currentSystemPermission)
    {
        switch (entry.EventType)
        {
            case HistoryEventType.Updated:
                return entry.EntityType switch
                {
                    HistoryEntryDtoExtensions.KnownEntityTypes.SystemPermission => UndoEligibility.Eligible(),
                    _ => UndoEligibility.Ineligible($"Cannot undo Update for entity {entry.EntityType}.")
                };
            case HistoryEventType.Deleted:
                {
                    var oldValue = GetPrimaryValue(entry);

                    return entry.EntityType switch
                    {
                        HistoryEntryDtoExtensions.KnownEntityTypes.SystemPermissionEnvironment => currentSystemPermission.Environments.Any(e => e.Environment.Equals(oldValue, StringComparison.OrdinalIgnoreCase))
                            ? UndoEligibility.Ineligible("An environment with this name already exists.")
                            : UndoEligibility.Eligible(),
                        HistoryEntryDtoExtensions.KnownEntityTypes.SystemPermissionRole => CheckRoleConflict(entry, currentSystemPermission),
                        _ => UndoEligibility.Ineligible($"Cannot undo Delete for entity {entry.EntityType}.")
                    };
                }
            default:
                return UndoEligibility.Ineligible($"Unsupported event type {entry.EventType} for undo.");
        }
    }

    private static UndoEligibility CheckRoleConflict(HistoryEntryDto entry, SystemPermissionDtoRead currentSystemPermission)
    {
        var userId = GetPrimaryValueFromChanges(entry, "User ID");
        if (string.IsNullOrEmpty(userId))
        {
            return UndoEligibility.Ineligible("Missing required User ID value.");
        }

        if (!TryGetEntityIdentifierFirstPart(entry, out var envName))
        {
            return UndoEligibility.Ineligible("Cannot determine environment name from history entry.");
        }

        var environment = currentSystemPermission.Environments.FirstOrDefault(e => e.Environment == envName);
        if (environment == null)
        {
            return UndoEligibility.Ineligible($"The Environment '{envName}' no longer exists.");
        }

        return environment.Permissions.Any(r => r.OId.Equals(userId, StringComparison.OrdinalIgnoreCase))
            ? UndoEligibility.Ineligible("A role for this user already exists in the environment.")
            : UndoEligibility.Eligible();
    }

    private static string? GetPrimaryValue(HistoryEntryDto entry)
    {
        var primaryField = entry.EntityType switch
        {
            HistoryEntryDtoExtensions.KnownEntityTypes.SystemPermissionEnvironment => "Environment",
            _ => null
        };

        return primaryField != null ? GetPrimaryValueFromChanges(entry, primaryField) : null;
    }

    #region Update Operations

    private async Task<ApiCallResult<SystemPermissionDtoRead>> ExecuteUndoUpdateAsync(HistoryEntryDto entry, int parentEntityId)
    {
        var oldValues = GetOldValuesFromChanges(entry);

        return entry.EntityType switch
        {
            HistoryEntryDtoExtensions.KnownEntityTypes.SystemPermission => await UndoSystemPermissionUpdate(parentEntityId, oldValues),
            _ => ApiCallResult<SystemPermissionDtoRead>.Error($"Undo for {entry.EntityType} updates is not supported.")
        };
    }

    private async Task<ApiCallResult<SystemPermissionDtoRead>> UndoSystemPermissionUpdate(int systemPermissionId, Dictionary<string, string?> oldValues)
    {
        if (!oldValues.TryGetValue("Description", out var description) || description == null)
        {
            return ApiCallResult<SystemPermissionDtoRead>.Error("Cannot undo: missing required Description value.");
        }

        var updateDto = new SystemPermissionDtoUpdate
        {
            Id = systemPermissionId,
            Description = description
        };

        var result = await _adminApiService.UpdateSystemPermission(updateDto);
        return result.IsSuccess
            ? ApiCallResult<SystemPermissionDtoRead>.Success(result.Result!)
            : ApiCallResult<SystemPermissionDtoRead>.Error(result.ErrorMessage ?? "Failed to undo system permission update.");
    }

    #endregion

    #region Delete Operations

    private async Task<ApiCallResult<SystemPermissionDtoRead>> ExecuteUndoDeleteAsync(HistoryEntryDto entry, SystemPermissionDtoRead entity)
    {
        var oldValues = GetOldValuesFromChanges(entry);

        // After recreating child entities, fetch the updated system permission
        var recreateResult = entry.EntityType switch
        {
            HistoryEntryDtoExtensions.KnownEntityTypes.SystemPermissionEnvironment => await UndoEnvironmentDelete(entity.Id, oldValues),
            HistoryEntryDtoExtensions.KnownEntityTypes.SystemPermissionRole => await UndoRoleDelete(entry, entity, oldValues),
            _ => null
        };

        if (recreateResult == null)
        {
            return ApiCallResult<SystemPermissionDtoRead>.Error($"Undo for {entry.EntityType} deletions is not supported.");
        }

        if (!recreateResult.IsSuccess)
        {
            return ApiCallResult<SystemPermissionDtoRead>.Error(recreateResult.ErrorMessage ?? "Failed to undo deletion.");
        }

        // Fetch and return the updated system permission
        var systemPermissionResult = await _adminApiService.GetSystemPermission(entity.Id);
        return systemPermissionResult.IsSuccess
            ? ApiCallResult<SystemPermissionDtoRead>.Success(systemPermissionResult.Result!)
            : ApiCallResult<SystemPermissionDtoRead>.Error("Child entity recreated but failed to fetch updated system permission.");
    }

    private async Task<ApiCallResult<object>> UndoEnvironmentDelete(int systemPermissionId, Dictionary<string, string?> oldValues)
    {
        if (!oldValues.TryGetValue("Environment", out var environment) || environment == null)
        {
            return ApiCallResult<object>.Error("Cannot undo: missing required Environment value.");
        }

        var createDto = new SystemPermissionEnvironmentDtoCreate
        {
            SystemPermissionId = systemPermissionId,
            Environment = environment
        };

        var result = await _adminApiService.CreateSystemPermissionEnvironment(createDto);
        return result.IsSuccess
            ? ApiCallResult<object>.Success(result.Result!)
            : ApiCallResult<object>.Error(result.ErrorMessage ?? "Failed to recreate system permission environment.");
    }

    private async Task<ApiCallResult<object>> UndoRoleDelete(HistoryEntryDto entry, SystemPermissionDtoRead entity, Dictionary<string, string?> oldValues)
    {
        if (!oldValues.TryGetValue("User ID", out var userId) || userId == null)
        {
            return ApiCallResult<object>.Error("Cannot undo: missing required User ID value.");
        }

        if (!oldValues.TryGetValue("RoleType", out var roleTypeStr) || roleTypeStr == null)
        {
            return ApiCallResult<object>.Error("Cannot undo: missing required RoleType value.");
        }

        if (!Enum.TryParse<Abstraction.Entities.IdentityServerConfig.SystemPermissions.SystemPermissionRoleType>(roleTypeStr, out var roleTypeValue))
        {
            return ApiCallResult<object>.Error("Cannot undo: invalid RoleType value.");
        }

        if (!TryGetEntityIdentifierFirstPart(entry, out var envName))
        {
            return ApiCallResult<object>.Error("Cannot determine environment name from history entry.");
        }

        var envId = entity.Environments.FirstOrDefault(e => e.Environment == envName)?.Id;
        if (envId == null)
        {
            return ApiCallResult<object>.Error($"The Environment '{envName}' no longer exists.");
        }

        var createDto = new SystemPermissionRoleDtoCreate
        {
            SystemPermissionEnvironmentId = envId.Value,
            OId = userId,
            RoleType = roleTypeValue,
        };

        var result = await _adminApiService.CreateSystemPermissionRole(createDto);
        return result.IsSuccess
            ? ApiCallResult<object>.Success(result.Result!)
            : ApiCallResult<object>.Error(result.ErrorMessage ?? "Failed to recreate system permission role.");
    }

    #endregion
}
