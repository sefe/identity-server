// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

using IdentityServer.Abstraction.DTO.Clients;
using IdentityServer.Abstraction.DTO.History;
using IdentityServer.Abstraction.Enums;

namespace IdentityServer.AdminPortal.Web.Services.History;

/// <summary>
/// Handles undo operations for Client and Client child entity history entries.
/// </summary>
public class ClientHistoryUndoService : EntityHistoryUndoServiceBase, IEntityHistoryUndoService<ClientDtoRead>
{
    private readonly IAdminApiService _adminApiService;

    private static readonly HashSet<string> _clientEntityTypes = new(StringComparer.OrdinalIgnoreCase)
    {
        HistoryEntryDtoExtensions.KnownEntityTypes.Client,
        HistoryEntryDtoExtensions.KnownEntityTypes.ClientRedirectUri,
        HistoryEntryDtoExtensions.KnownEntityTypes.ClientPostLogoutRedirectUri,
        HistoryEntryDtoExtensions.KnownEntityTypes.ClientCorsOrigin,
        HistoryEntryDtoExtensions.KnownEntityTypes.ClientGrantType,
        HistoryEntryDtoExtensions.KnownEntityTypes.ClientScope,
        HistoryEntryDtoExtensions.KnownEntityTypes.ClientRole,
        HistoryEntryDtoExtensions.KnownEntityTypes.ClientRoleMapping,
        HistoryEntryDtoExtensions.KnownEntityTypes.ClientEntraApp
        // Secrets are not undoable
    };

    public ClientHistoryUndoService(IAdminApiService adminApiService)
    {
        _adminApiService = adminApiService;
    }

    /// <inheritdoc />
    public IReadOnlySet<string> SupportedEntityTypes => _clientEntityTypes;

    /// <inheritdoc />
    public bool CanHandle(string entityType) => _clientEntityTypes.Contains(entityType);

    /// <inheritdoc />
    public UndoEligibility CanUndo(HistoryEntryDto entry, ClientDtoRead? currentEntity)
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
    public async Task<ApiCallResult<ClientDtoRead>> ExecuteUndoAsync(HistoryEntryDto entry, ClientDtoRead entity)
    {
        return entry.EventType switch
        {
            HistoryEventType.Updated => await ExecuteUndoUpdateAsync(entry, entity.Id),
            HistoryEventType.Deleted => await ExecuteUndoDeleteAsync(entry, entity),
            _ => ApiCallResult<ClientDtoRead>.Error("Unsupported event type for undo.")
        };
    }

    private static UndoEligibility CheckConflicts(HistoryEntryDto entry, ClientDtoRead currentClient)
    {
        if (entry.EventType != HistoryEventType.Deleted)
        {
            return UndoEligibility.Eligible();
        }

        var oldValue = GetPrimaryValue(entry);

        return entry.EntityType switch
        {
            HistoryEntryDtoExtensions.KnownEntityTypes.ClientRedirectUri => currentClient.RedirectUris.Any(r => r.RedirectUri.Equals(oldValue, StringComparison.OrdinalIgnoreCase))
                ? UndoEligibility.Ineligible("A redirect URI with this value already exists.")
                : UndoEligibility.Eligible(),

            HistoryEntryDtoExtensions.KnownEntityTypes.ClientPostLogoutRedirectUri => currentClient.PostLogoutRedirectUris.Any(r => r.PostLogoutRedirectUri.Equals(oldValue, StringComparison.OrdinalIgnoreCase))
                ? UndoEligibility.Ineligible("A post-logout redirect URI with this value already exists.")
                : UndoEligibility.Eligible(),

            HistoryEntryDtoExtensions.KnownEntityTypes.ClientCorsOrigin => currentClient.AllowedCorsOrigins.Any(c => c.Origin.Equals(oldValue, StringComparison.OrdinalIgnoreCase))
                ? UndoEligibility.Ineligible("A CORS origin with this value already exists.")
                : UndoEligibility.Eligible(),

            HistoryEntryDtoExtensions.KnownEntityTypes.ClientGrantType => currentClient.AllowedGrantTypes.Any(g => g.GrantType.Equals(oldValue, StringComparison.OrdinalIgnoreCase))
                ? UndoEligibility.Ineligible("A grant type with this value already exists.")
                : UndoEligibility.Eligible(),

            HistoryEntryDtoExtensions.KnownEntityTypes.ClientScope => currentClient.AllowedScopes.Any(s => s.Scope.Equals(oldValue, StringComparison.OrdinalIgnoreCase))
                ? UndoEligibility.Ineligible("A scope with this value already exists.")
                : UndoEligibility.Eligible(),

            HistoryEntryDtoExtensions.KnownEntityTypes.ClientRole => currentClient.Roles.Any(r => r.RoleName.Equals(oldValue, StringComparison.OrdinalIgnoreCase))
                ? UndoEligibility.Ineligible("A role with this name already exists.")
                : UndoEligibility.Eligible(),

            HistoryEntryDtoExtensions.KnownEntityTypes.ClientRoleMapping => CheckRoleMappingConflict(entry, currentClient),

            _ => UndoEligibility.Eligible()
        };
    }

    private static UndoEligibility CheckRoleMappingConflict(HistoryEntryDto entry, ClientDtoRead currentClient)
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

        if (!Enum.TryParse<Abstraction.Entities.IdentityServerConfig.ClientRoleMapType>(mappingTypeStr, out var mappingType))
        {
            return UndoEligibility.Eligible();
        }

        if (!TryGetEntityIdentifierFirstPart(entry, out var ClientRoleName))
        {
            return UndoEligibility.Ineligible("Cannot determine role ID from EntityIdentifier.");
        }

        var role = currentClient.Roles.FirstOrDefault(r => r.RoleName.Equals(ClientRoleName, StringComparison.OrdinalIgnoreCase));
        if (role == null)
        {
            return UndoEligibility.Ineligible($"Role '{ClientRoleName}' no longer exists.");
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
            HistoryEntryDtoExtensions.KnownEntityTypes.ClientRedirectUri => "RedirectUri",
            HistoryEntryDtoExtensions.KnownEntityTypes.ClientPostLogoutRedirectUri => "PostLogoutRedirectUri",
            HistoryEntryDtoExtensions.KnownEntityTypes.ClientCorsOrigin => "Origin",
            HistoryEntryDtoExtensions.KnownEntityTypes.ClientGrantType => "GrantType",
            HistoryEntryDtoExtensions.KnownEntityTypes.ClientScope => "Scope",
            HistoryEntryDtoExtensions.KnownEntityTypes.ClientRole => "RoleName",
            _ => null
        };

        return primaryField != null ? GetPrimaryValueFromChanges(entry, primaryField) : null;
    }

    #region Update Operations

    private async Task<ApiCallResult<ClientDtoRead>> ExecuteUndoUpdateAsync(HistoryEntryDto entry, int parentEntityId)
    {
        var oldValues = GetOldValuesFromChanges(entry);

        return entry.EntityType switch
        {
            HistoryEntryDtoExtensions.KnownEntityTypes.Client => await UndoClientUpdate(parentEntityId, oldValues),
            _ => ApiCallResult<ClientDtoRead>.Error($"Undo for {entry.EntityType} updates is not supported.")
        };
    }

    private async Task<ApiCallResult<ClientDtoRead>> UndoClientUpdate(int clientId, Dictionary<string, string?> oldValues)
    {
        var updateDto = new ClientDtoUpdate { Id = clientId };

        if (oldValues.TryGetValue("ClientName", out var clientName))
        {
            updateDto.ClientName = clientName;
        }
        if (oldValues.TryGetValue("Description", out var description))
        {
            updateDto.Description = description;
        }
        if (oldValues.TryGetValue("Enabled", out var enabled) && bool.TryParse(enabled, out var enabledValue))
        {
            updateDto.Enabled = enabledValue;
        }
        if (oldValues.TryGetValue("RequirePkce", out var requirePkce) && bool.TryParse(requirePkce, out var requirePkceValue))
        {
            updateDto.RequirePkce = requirePkceValue;
        }
        if (oldValues.TryGetValue("RequireClientSecret", out var requireClientSecret) && bool.TryParse(requireClientSecret, out var requireClientSecretValue))
        {
            updateDto.RequireClientSecret = requireClientSecretValue;
        }
        if (oldValues.TryGetValue("AllowOfflineAccess", out var allowOfflineAccess) && bool.TryParse(allowOfflineAccess, out var allowOfflineAccessValue))
        {
            updateDto.AllowOfflineAccess = allowOfflineAccessValue;
        }

        var result = await _adminApiService.UpdateClient(updateDto);
        return result.IsSuccess
            ? ApiCallResult<ClientDtoRead>.Success(result.Result!)
            : ApiCallResult<ClientDtoRead>.Error(result.ErrorMessage ?? "Failed to undo client update.");
    }

    #endregion

    #region Delete Operations

    private async Task<ApiCallResult<ClientDtoRead>> ExecuteUndoDeleteAsync(HistoryEntryDto entry, ClientDtoRead entity)
    {
        var oldValues = GetOldValuesFromChanges(entry);

        // After recreating child entities, fetch the updated client
        var recreateResult = entry.EntityType switch
        {
            HistoryEntryDtoExtensions.KnownEntityTypes.ClientRedirectUri => await UndoRedirectUriDelete(entity.Id, oldValues),
            HistoryEntryDtoExtensions.KnownEntityTypes.ClientPostLogoutRedirectUri => await UndoPostLogoutRedirectUriDelete(entity.Id, oldValues),
            HistoryEntryDtoExtensions.KnownEntityTypes.ClientCorsOrigin => await UndoCorsOriginDelete(entity.Id, oldValues),
            HistoryEntryDtoExtensions.KnownEntityTypes.ClientGrantType => await UndoGrantDelete(entity.Id, oldValues),
            HistoryEntryDtoExtensions.KnownEntityTypes.ClientScope => await UndoScopeDelete(entity.Id, oldValues),
            HistoryEntryDtoExtensions.KnownEntityTypes.ClientRole => await UndoRoleDelete(entity.Id, oldValues),
            HistoryEntryDtoExtensions.KnownEntityTypes.ClientRoleMapping => await UndoRoleMappingDelete(entry, entity, oldValues),
            _ => null
        };

        if (recreateResult == null)
        {
            return ApiCallResult<ClientDtoRead>.Error($"Undo for {entry.EntityType} deletions is not supported.");
        }

        if (!recreateResult.IsSuccess)
        {
            return ApiCallResult<ClientDtoRead>.Error(recreateResult.ErrorMessage ?? "Failed to undo deletion.");
        }

        // Fetch and return the updated client
        var clientResult = await _adminApiService.GetClient(entity.Id);
        return clientResult.IsSuccess
            ? ApiCallResult<ClientDtoRead>.Success(clientResult.Result!)
            : ApiCallResult<ClientDtoRead>.Error("Child entity recreated but failed to fetch updated client.");
    }

    private async Task<ApiCallResult<object>> UndoRedirectUriDelete(int clientId, Dictionary<string, string?> oldValues)
    {
        if (!oldValues.TryGetValue("RedirectUri", out var redirectUri) || redirectUri == null)
        {
            return ApiCallResult<object>.Error("Cannot undo: missing required RedirectUri value.");
        }

        var createDto = new ClientPropertyRedirectUriDtoCreate
        {
            ClientId = clientId,
            RedirectUri = redirectUri
        };

        var result = await _adminApiService.AddClientRedirectUri(createDto);
        return result.IsSuccess
            ? ApiCallResult<object>.Success(result.Result!)
            : ApiCallResult<object>.Error(result.ErrorMessage ?? "Failed to recreate redirect URI.");
    }

    private async Task<ApiCallResult<object>> UndoPostLogoutRedirectUriDelete(int clientId, Dictionary<string, string?> oldValues)
    {
        if (!oldValues.TryGetValue("PostLogoutRedirectUri", out var postLogoutRedirectUri) || postLogoutRedirectUri == null)
        {
            return ApiCallResult<object>.Error("Cannot undo: missing required PostLogoutRedirectUri value.");
        }

        var createDto = new ClientPropertyPostLogoutRedirectUriDtoCreate
        {
            ClientId = clientId,
            PostLogoutRedirectUri = postLogoutRedirectUri
        };

        var result = await _adminApiService.AddClientPostLogoutRedirectUri(createDto);
        return result.IsSuccess
            ? ApiCallResult<object>.Success(result.Result!)
            : ApiCallResult<object>.Error(result.ErrorMessage ?? "Failed to recreate post-logout redirect URI.");
    }

    private async Task<ApiCallResult<object>> UndoCorsOriginDelete(int clientId, Dictionary<string, string?> oldValues)
    {
        if (!oldValues.TryGetValue("Origin", out var origin) || origin == null)
        {
            return ApiCallResult<object>.Error("Cannot undo: missing required Origin value.");
        }

        var createDto = new ClientPropertyCorsOriginDtoCreate
        {
            ClientId = clientId,
            Origin = origin
        };

        var result = await _adminApiService.AddClientCorsUri(createDto);
        return result.IsSuccess
            ? ApiCallResult<object>.Success(result.Result!)
            : ApiCallResult<object>.Error(result.ErrorMessage ?? "Failed to recreate CORS origin.");
    }

    private async Task<ApiCallResult<object>> UndoGrantDelete(int clientId, Dictionary<string, string?> oldValues)
    {
        if (!oldValues.TryGetValue("GrantType", out var grantType) || grantType == null)
        {
            return ApiCallResult<object>.Error("Cannot undo: missing required GrantType value.");
        }

        var createDto = new ClientPropertyGrantDtoCreate
        {
            ClientId = clientId,
            GrantType = grantType
        };

        var result = await _adminApiService.AddClientGrant(createDto);
        return result.IsSuccess
            ? ApiCallResult<object>.Success(result.Result!)
            : ApiCallResult<object>.Error(result.ErrorMessage ?? "Failed to recreate grant type.");
    }

    private async Task<ApiCallResult<object>> UndoScopeDelete(int clientId, Dictionary<string, string?> oldValues)
    {
        if (!oldValues.TryGetValue("Scope", out var scope) || scope == null)
        {
            return ApiCallResult<object>.Error("Cannot undo: missing required Scope value.");
        }

        var createDto = new ClientPropertyScopeDtoCreate
        {
            ClientId = clientId,
            Scope = scope
        };

        var result = await _adminApiService.AddClientScope(createDto);
        return result.IsSuccess
            ? ApiCallResult<object>.Success(result.Result!)
            : ApiCallResult<object>.Error(result.ErrorMessage ?? "Failed to recreate scope.");
    }

    private async Task<ApiCallResult<object>> UndoRoleDelete(int clientId, Dictionary<string, string?> oldValues)
    {
        if (!oldValues.TryGetValue("RoleName", out var roleName) || roleName == null)
        {
            return ApiCallResult<object>.Error("Cannot undo: missing required RoleName value.");
        }

        var createDto = new ClientPropertyRoleDtoCreate
        {
            ClientId = clientId,
            RoleName = roleName
        };

        var result = await _adminApiService.AddClientRole(createDto);
        return result.IsSuccess
            ? ApiCallResult<object>.Success(result.Result!)
            : ApiCallResult<object>.Error(result.ErrorMessage ?? "Failed to recreate role.");
    }

    private async Task<ApiCallResult<object>> UndoRoleMappingDelete(HistoryEntryDto entry, ClientDtoRead entity, Dictionary<string, string?> oldValues)
    {
        if (!TryGetEntityIdentifierFirstPart(entry, out var clientRoleName))
        {
            return ApiCallResult<object>.Error("Cannot determine role ID from EntityIdentifier.");
        }

        var role = entity.Roles.FirstOrDefault(r => r.RoleName.Equals(clientRoleName, StringComparison.OrdinalIgnoreCase));
        if (role == null)
        {
            return ApiCallResult<object>.Error($"Role '{clientRoleName}' no longer exists.");
        }

        if (!oldValues.TryGetValue("Value", out var value) || value == null)
        {
            return ApiCallResult<object>.Error("Cannot undo: missing required Value for role mapping.");
        }

        if (!oldValues.TryGetValue("MappingType", out var mappingTypeStr) ||
            !Enum.TryParse<Abstraction.Entities.IdentityServerConfig.ClientRoleMapType>(mappingTypeStr, out var mappingType))
        {
            return ApiCallResult<object>.Error("Cannot undo: missing or invalid MappingType.");
        }

        var createDto = new ClientPropertyRoleMappingDtoCreate
        {
            ClientId = entity.Id,
            ClientRoleId = role.Id,
            MappingType = mappingType,
            Value = value
        };

        var result = await _adminApiService.AddClientRoleMapping(createDto);
        return result.IsSuccess
            ? ApiCallResult<object>.Success(result.Result!)
            : ApiCallResult<object>.Error(result.ErrorMessage ?? "Failed to recreate client role mapping.");
    }

    #endregion
}
