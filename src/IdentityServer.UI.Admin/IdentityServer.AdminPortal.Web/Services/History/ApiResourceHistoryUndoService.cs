using IdentityServer.Abstraction.DTO.ApiResources;
using IdentityServer.Abstraction.DTO.History;
using IdentityServer.Abstraction.Enums;

namespace IdentityServer.AdminPortal.Web.Services.History;

/// <summary>
/// Handles undo operations for ApiResource and ApiResource child entity history entries.
/// </summary>
public class ApiResourceHistoryUndoService : EntityHistoryUndoServiceBase, IEntityHistoryUndoService<ApiResourceDtoRead>
{
    private readonly IAdminApiService _adminApiService;

    private static readonly HashSet<string> _apiResourceEntityTypes = new(StringComparer.OrdinalIgnoreCase)
    {
        HistoryEntryDtoExtensions.KnownEntityTypes.ApiResource,
        HistoryEntryDtoExtensions.KnownEntityTypes.ApiResourceRole,
        HistoryEntryDtoExtensions.KnownEntityTypes.ApiResourceRoleMapping,
        HistoryEntryDtoExtensions.KnownEntityTypes.ApiScope,
        // Secrets are not undoable
    };

    public ApiResourceHistoryUndoService(IAdminApiService adminApiService)
    {
        _adminApiService = adminApiService;
    }

    /// <inheritdoc />
    public IReadOnlySet<string> SupportedEntityTypes => _apiResourceEntityTypes;

    /// <inheritdoc />
    public bool CanHandle(string entityType) => _apiResourceEntityTypes.Contains(entityType);

    /// <inheritdoc />
    public UndoEligibility CanUndo(HistoryEntryDto entry, ApiResourceDtoRead? currentEntity)
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
    public async Task<ApiCallResult<ApiResourceDtoRead>> ExecuteUndoAsync(HistoryEntryDto entry, ApiResourceDtoRead entity)
    {
        return entry.EventType switch
        {
            HistoryEventType.Updated => await ExecuteUndoUpdateAsync(entry, entity),
            HistoryEventType.Deleted => await ExecuteUndoDeleteAsync(entry, entity),
            _ => ApiCallResult<ApiResourceDtoRead>.Error("Unsupported event type for undo.")
        };
    }

    private static UndoEligibility CheckConflicts(HistoryEntryDto entry, ApiResourceDtoRead currentApiResource)
    {
        if (entry.EventType == HistoryEventType.Updated)
        {
            return entry.EntityType switch
            {
                HistoryEntryDtoExtensions.KnownEntityTypes.ApiScope => CheckScopeExistsForUpdate(entry, currentApiResource),
                _ => UndoEligibility.Eligible()
            };
        }

        var oldValue = GetPrimaryValue(entry);

        return entry.EntityType switch
        {
            HistoryEntryDtoExtensions.KnownEntityTypes.ApiScope => currentApiResource.Scopes.Any(s => s.Scope.Equals(oldValue, StringComparison.OrdinalIgnoreCase))
                ? UndoEligibility.Ineligible("A scope with this name already exists.")
                : UndoEligibility.Eligible(),

            HistoryEntryDtoExtensions.KnownEntityTypes.ApiResourceRole => currentApiResource.Roles.Any(r => r.RoleName.Equals(oldValue, StringComparison.OrdinalIgnoreCase))
                ? UndoEligibility.Ineligible("A role with this name already exists.")
                : UndoEligibility.Eligible(),

            HistoryEntryDtoExtensions.KnownEntityTypes.ApiResourceRoleMapping => CheckRoleMappingConflict(entry, currentApiResource),

            _ => UndoEligibility.Eligible()
        };
    }

    private static UndoEligibility CheckScopeExistsForUpdate(HistoryEntryDto entry, ApiResourceDtoRead currentApiResource)
    {
        if (string.IsNullOrEmpty(entry.EntityIdentifier))
        {
            return UndoEligibility.Ineligible("Cannot determine scope name from history entry.");
        }

        var scopeExists = currentApiResource.Scopes.Any(s => s.Scope.Equals(entry.EntityIdentifier, StringComparison.OrdinalIgnoreCase));
        return scopeExists
            ? UndoEligibility.Eligible()
            : UndoEligibility.Ineligible("The scope no longer exists on this API resource.");
    }

    private static UndoEligibility CheckRoleMappingConflict(HistoryEntryDto entry, ApiResourceDtoRead currentApiResource)
    {
        // Extract the values from the history entry
        var valueChange = entry.Changes.FirstOrDefault(c => c.FieldName.Equals("Value", StringComparison.OrdinalIgnoreCase));
        var mappingTypeChange = entry.Changes.FirstOrDefault(c => c.FieldName.Equals("MappingType", StringComparison.OrdinalIgnoreCase));

        if (valueChange == null || mappingTypeChange == null)
        {
            // Missing required data, can't check for duplicates
            return UndoEligibility.Eligible();
        }

        var value = valueChange.OldValue;
        var mappingTypeStr = mappingTypeChange.OldValue;

        if (string.IsNullOrEmpty(value) || string.IsNullOrEmpty(mappingTypeStr))
        {
            return UndoEligibility.Eligible();
        }

        if (!Enum.TryParse<Abstraction.Entities.IdentityServerConfig.RoleMapType>(mappingTypeStr, out var mappingType))
        {
            return UndoEligibility.Eligible();
        }

        if (!TryGetEntityIdentifierFirstPart(entry, out var apiResourceRoleName))
        {
            return UndoEligibility.Ineligible("Cannot determine role ID from EntityIdentifier.");
        }

        var role = currentApiResource.Roles.FirstOrDefault(r => r.RoleName.Equals(apiResourceRoleName, StringComparison.OrdinalIgnoreCase));
        if (role == null)
        {
            return UndoEligibility.Ineligible($"Role '{apiResourceRoleName}' no longer exists.");
        }

        var duplicateExists = role.Mappings.Any(m =>
            m.Value.Equals(value, StringComparison.OrdinalIgnoreCase) &&
            m.MappingType == mappingType);

        return duplicateExists
            ? UndoEligibility.Ineligible("A role mapping with this combination already exists.")
            : UndoEligibility.Eligible();
    }

    private static string? GetPrimaryValue(HistoryEntryDto entry)
    {
        var primaryField = entry.EntityType switch
        {
            HistoryEntryDtoExtensions.KnownEntityTypes.ApiScope => "Name",
            HistoryEntryDtoExtensions.KnownEntityTypes.ApiResourceRole => "RoleName",
            _ => null
        };

        return primaryField != null ? GetPrimaryValueFromChanges(entry, primaryField) : null;
    }

    #region Update Operations

    private async Task<ApiCallResult<ApiResourceDtoRead>> ExecuteUndoUpdateAsync(HistoryEntryDto entry, ApiResourceDtoRead entity)
    {
        var oldValues = GetOldValuesFromChanges(entry);

        return entry.EntityType switch
        {
            HistoryEntryDtoExtensions.KnownEntityTypes.ApiResource => await UndoApiResourceUpdate(entity.Id, oldValues),
            HistoryEntryDtoExtensions.KnownEntityTypes.ApiScope => await UndoScopeUpdate(entry, oldValues, entity),
            _ => ApiCallResult<ApiResourceDtoRead>.Error($"Undo for {entry.EntityType} updates is not supported.")
        };
    }

    private async Task<ApiCallResult<ApiResourceDtoRead>> UndoApiResourceUpdate(int apiResourceId, Dictionary<string, string?> oldValues)
    {
        var updateDto = new ApiResourceDtoUpdate { Id = apiResourceId };

        if (oldValues.TryGetValue("DisplayName", out var displayName))
        {
            updateDto.DisplayName = displayName;
        }
        if (oldValues.TryGetValue("Description", out var description))
        {
            updateDto.Description = description;
        }
        if (oldValues.TryGetValue("Enabled", out var enabled) && bool.TryParse(enabled, out var enabledValue))
        {
            updateDto.Enabled = enabledValue;
        }

        var result = await _adminApiService.UpdateApiResource(updateDto);
        return result.IsSuccess
            ? ApiCallResult<ApiResourceDtoRead>.Success(result.Result!)
            : ApiCallResult<ApiResourceDtoRead>.Error(result.ErrorMessage ?? "Failed to undo API resource update.");
    }

    private async Task<ApiCallResult<ApiResourceDtoRead>> UndoScopeUpdate(HistoryEntryDto entry, Dictionary<string, string?> oldValues, ApiResourceDtoRead entity)
    {
        var scopeId = entity.Scopes.FirstOrDefault(s => s.Scope.Equals(entry.EntityIdentifier, StringComparison.OrdinalIgnoreCase))?.Id;
        if (scopeId == null)
        {
            return ApiCallResult<ApiResourceDtoRead>.Error("Cannot determine scope ID of the API Resource.");
        }

        var updateDto = new ApiResourcePropertyScopeDtoUpdate { Id = scopeId.Value };

        if (oldValues.TryGetValue("Enabled", out var enabled) && bool.TryParse(enabled, out var enabledValue))
        {
            updateDto.Enabled = enabledValue;
        }
        if (oldValues.TryGetValue("Required", out var required) && bool.TryParse(required, out var requiredValue))
        {
            updateDto.Required = requiredValue;
        }
        if (oldValues.TryGetValue("DisplayName", out var displayName))
        {
            updateDto.DisplayName = displayName;
        }
        if (oldValues.TryGetValue("Description", out var description))
        {
            updateDto.Description = description;
        }

        var result = await _adminApiService.UpdateApiResourceScope(updateDto);
        if (!result.IsSuccess)
        {
            return ApiCallResult<ApiResourceDtoRead>.Error(result.ErrorMessage ?? "Failed to undo API resource scope update.");
        }

        // Fetch and return the updated API resource
        var apiResourceResult = await _adminApiService.GetApiResource(entity.Id);
        return apiResourceResult.IsSuccess
            ? ApiCallResult<ApiResourceDtoRead>.Success(apiResourceResult.Result!)
            : ApiCallResult<ApiResourceDtoRead>.Error("Scope updated but failed to fetch updated API resource.");
    }

    #endregion

    #region Delete Operations

    private async Task<ApiCallResult<ApiResourceDtoRead>> ExecuteUndoDeleteAsync(HistoryEntryDto entry, ApiResourceDtoRead entity)
    {
        var oldValues = GetOldValuesFromChanges(entry);

        // After recreating child entities, fetch the updated API resource
        var recreateResult = entry.EntityType switch
        {
            HistoryEntryDtoExtensions.KnownEntityTypes.ApiScope => await UndoScopeDelete(entity.Id, entity.Name, oldValues),
            HistoryEntryDtoExtensions.KnownEntityTypes.ApiResourceRole => await UndoRoleDelete(entity.Id, oldValues),
            HistoryEntryDtoExtensions.KnownEntityTypes.ApiResourceRoleMapping => await UndoRoleMappingDelete(entry, entity, oldValues),
            _ => null
        };

        if (recreateResult == null)
        {
            return ApiCallResult<ApiResourceDtoRead>.Error($"Undo for {entry.EntityType} deletions is not supported.");
        }

        if (!recreateResult.IsSuccess)
        {
            return ApiCallResult<ApiResourceDtoRead>.Error(recreateResult.ErrorMessage ?? "Failed to undo deletion.");
        }

        // Fetch and return the updated API resource
        var apiResourceResult = await _adminApiService.GetApiResource(entity.Id);
        return apiResourceResult.IsSuccess
            ? ApiCallResult<ApiResourceDtoRead>.Success(apiResourceResult.Result!)
            : ApiCallResult<ApiResourceDtoRead>.Error("Child entity recreated but failed to fetch updated API resource.");
    }

    private async Task<ApiCallResult<object>> UndoScopeDelete(int apiResourceId, string apiName, Dictionary<string, string?> oldValues)
    {
        if (string.IsNullOrEmpty(apiName))
        {
            return ApiCallResult<object>.Error("Cannot undo: API resource name is missing.");
        }
        if ((!oldValues.TryGetValue("Name", out var scope) || scope == null) && (!oldValues.TryGetValue("Scope", out scope) || scope == null))
        {
            return ApiCallResult<object>.Error("Cannot undo: missing required scope name value.");
        }
        if (!scope.StartsWith(apiName + ".", StringComparison.OrdinalIgnoreCase))
        {
            return ApiCallResult<object>.Error("Cannot undo: scope name does not match expected format.");
        }

        var createDto = new ApiResourcePropertyScopeDtoCreate
        {
            ApiResourceId = apiResourceId,
            Name = scope[(apiName.Length + 1)..],
            DisplayName = oldValues.TryGetValue("DisplayName", out var displayName) ? displayName ?? scope : scope,
            Description = oldValues.TryGetValue("Description", out var description) ? description : null,
            Enabled = !oldValues.TryGetValue("Enabled", out var enabled) || !bool.TryParse(enabled, out var enabledValue) || enabledValue,
            Required = oldValues.TryGetValue("Required", out var required) && bool.TryParse(required, out var requiredValue) && requiredValue
        };

        var result = await _adminApiService.AddApiResourceScope(createDto);
        return result.IsSuccess
            ? ApiCallResult<object>.Success(result.Result!)
            : ApiCallResult<object>.Error(result.ErrorMessage ?? "Failed to recreate API resource scope.");
    }

    private async Task<ApiCallResult<object>> UndoRoleDelete(int apiResourceId, Dictionary<string, string?> oldValues)
    {
        if (!oldValues.TryGetValue("RoleName", out var roleName) || roleName == null)
        {
            return ApiCallResult<object>.Error("Cannot undo: missing required RoleName value.");
        }

        var createDto = new ApiResourcePropertyRoleDtoCreate
        {
            ApiResourceId = apiResourceId,
            RoleName = roleName
        };

        var result = await _adminApiService.AddApiResourceRole(createDto);
        return result.IsSuccess
            ? ApiCallResult<object>.Success(result.Result!)
            : ApiCallResult<object>.Error(result.ErrorMessage ?? "Failed to recreate API resource role.");
    }

    private async Task<ApiCallResult<object>> UndoRoleMappingDelete(HistoryEntryDto entry, ApiResourceDtoRead entity, Dictionary<string, string?> oldValues)
    {
        if (!TryGetEntityIdentifierFirstPart(entry, out var apiResourceRoleName))
        {
            return ApiCallResult<object>.Error("Cannot determine role ID from EntityIdentifier.");
        }

        var role = entity.Roles.FirstOrDefault(r => r.RoleName.Equals(apiResourceRoleName, StringComparison.OrdinalIgnoreCase));
        if (role == null)
        {
            return ApiCallResult<object>.Error($"Role '{apiResourceRoleName}' no longer exists.");
        }

        if (!oldValues.TryGetValue("Value", out var value) || value == null)
        {
            return ApiCallResult<object>.Error("Cannot undo: missing required Value for role mapping.");
        }

        if (!oldValues.TryGetValue("MappingType", out var mappingTypeStr) ||
            !Enum.TryParse<Abstraction.Entities.IdentityServerConfig.RoleMapType>(mappingTypeStr, out var mappingType))
        {
            return ApiCallResult<object>.Error("Cannot undo: missing or invalid MappingType.");
        }

        var createDto = new ApiResourcePropertyRoleMappingDtoCreate
        {
            ApiResourceId = entity.Id,
            ApiResourceRoleId = role.Id,
            MappingType = mappingType,
            Value = value
        };

        var result = await _adminApiService.AddApiResourceRoleMapping(createDto);
        return result.IsSuccess
            ? ApiCallResult<object>.Success(result.Result!)
            : ApiCallResult<object>.Error(result.ErrorMessage ?? "Failed to recreate API resource role mapping.");
    }

    #endregion
}
