// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

using System.Security.Claims;
using IdentityServer.Abstraction.Contracts;
using IdentityServer.Abstraction.Entities.IdentityServerConfig;
using IdentityServer.Data.DuendeEntityExtensions;
using IdentityServer.Data.Entities.Roles;
using static IdentityServer.Abstraction.Constants;

namespace IdentityServer.Services.ApiRoles;

public class ApiClientRoleClaimMapper : IApiClientRoleClaimMapper
{
    private readonly IStorage<ApiResourceExt> _apiStorage;
    private readonly ILogger<ApiClientRoleClaimMapper> _logger;

    public ApiClientRoleClaimMapper(IStorage<ApiResourceExt> apiStorage, ILogger<ApiClientRoleClaimMapper> logger)
    {
        _apiStorage = apiStorage;
        _logger = logger;
    }

    public async IAsyncEnumerable<Claim> ProcessApiRoleMappingsForClientIdAsync(IEnumerable<string> apiResourceNames, string clientId)
    {
        foreach (var apiResourceName in apiResourceNames)
        {
            await foreach (var mappedRoleClaim in MapApiRolesToClaimsAsync(apiResourceName, clientId))
            {
                yield return mappedRoleClaim;
            }
        }
    }

    internal async IAsyncEnumerable<Claim> MapApiRolesToClaimsAsync(string apiResourceName, string clientId)
    {
        var requestedApi = await _apiStorage.FirstOrDefaultAsync(x => x.Name == apiResourceName);
        if (requestedApi == null)
        {
            _logger.LogWarning("API Resource not found by Name: '{ApiResourceName}'", apiResourceName);
            yield break;
        }

        if (requestedApi.Roles == null || requestedApi.Roles.Count == 0)
        {
            _logger.LogDebug("API Resource '{ApiResourceName}' doesn't have any roles", apiResourceName);
            yield break;
        }

        if (requestedApi.Roles.All(cr => cr.Mappings == null || cr.Mappings.Count == 0))
        {
            _logger.LogDebug("API Resource '{ApiResourceName}' custom roles don't have any mappings", apiResourceName);
            yield break;
        }

        foreach (var customRole in requestedApi.Roles)
        {
            foreach (var claim in ProcessCustomRole(apiResourceName, customRole, clientId))
            {
                yield return claim;
            }
        }
    }

    internal IEnumerable<Claim> ProcessCustomRole(string apiName, ApiResourceRole customRole, string clientId)
    {
        if (customRole.Mappings == null || customRole.Mappings.Count == 0)
        {
            _logger.LogDebug("API Resource '{ApiResourceName}' custom role '{RoleName}' doesn't have any mappings", apiName, customRole.RoleName);
            yield break;
        }

        foreach (var roleMapping in customRole.Mappings)
        {
            if (!IsValidRoleMapping(apiName, customRole.RoleName, roleMapping))
            {
                continue;
            }

            if (roleMapping.MappingType is RoleMapType.ClientId && string.Equals(clientId, roleMapping.Value, StringComparison.OrdinalIgnoreCase))
            {
                yield return new Claim(ClaimNames.UserRole, customRole.RoleName);
            }
        }
    }

    internal bool IsValidRoleMapping(string apiName, string roleName, RoleMapping? roleMapping)
    {
        if (roleMapping == null)
        {
            _logger.LogWarning("API Resource '{ApiResourceName}' custom role '{RoleName}' has a null mapping", apiName, roleName);
            return false;
        }

        if (string.IsNullOrEmpty(roleMapping.Value))
        {
            _logger.LogWarning("API Resource '{ApiResourceName}' custom role '{RoleName}' has an empty mapping value", apiName, roleName);
            return false;
        }

        return true;
    }
}
