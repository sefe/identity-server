using System.Security.Claims;
using IdentityServer.Abstraction.Contracts;
using IdentityServer.Abstraction.Contracts.MicrosoftGraph;
using IdentityServer.Abstraction.Entities.IdentityServerConfig;
using IdentityServer.Data.DuendeEntityExtensions;
using IdentityServer.Data.Entities.Roles;
using static IdentityServer.Abstraction.Constants;

namespace IdentityServer.Services.ApiRoles;

public class ApiUserRoleClaimMapper : IApiUserRoleClaimMapper
{
    private readonly IStorage<ApiResourceExt> _apiStorage;
    private readonly IEntraUserService _entraService;
    private readonly ILogger<ApiUserRoleClaimMapper> _logger;

    public ApiUserRoleClaimMapper(IStorage<ApiResourceExt> apiStorage, IEntraUserService entraService, ILogger<ApiUserRoleClaimMapper> logger)
    {
        _apiStorage = apiStorage;
        _entraService = entraService;
        _logger = logger;
    }

    public async IAsyncEnumerable<Claim> ProcessApiRoleMappingsForUserAsync(IEnumerable<string> apiResourceNames, string userId)
    {
        foreach (var apiResourceName in apiResourceNames)
        {
            await foreach (var mappedRoleClaim in MapUserGroupsToApiRolesAsync(apiResourceName, userId))
            {
                yield return mappedRoleClaim;
            }
        }
    }

    public async IAsyncEnumerable<Claim> MapUserGroupsToApiRolesAsync(string apiResourceName, string userId)
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

        List<string> groupIdsToCheck = GetSecurityGroupIdsFromRoleMappings(requestedApi);

        HashSet<string> userMembershipGroups = await GetUserMembershipInMappedGroupsAsync(userId, groupIdsToCheck);

        foreach (var mappedRoleClaim in MapApiRolesToClaims(requestedApi.Roles, apiResourceName, userId, userMembershipGroups))
        {
            yield return mappedRoleClaim;
        }
    }

    internal async Task<HashSet<string>> GetUserMembershipInMappedGroupsAsync(string userId, List<string> groupIdsToCheck)
    {
        if (groupIdsToCheck.Count > 0)
        {
            return (await _entraService.GetUserMembershipInGroups(userId, groupIdsToCheck)).Select(g => g.Id).ToHashSet(StringComparer.OrdinalIgnoreCase);
        }
        else
        {
            return new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        }
    }

    internal static List<string> GetSecurityGroupIdsFromRoleMappings(ApiResourceExt requestedClient)
    {
        return requestedClient.Roles
            .SelectMany(r => r.Mappings ?? Enumerable.Empty<RoleMapping>())
            .Where(m => m != null && m.MappingType == RoleMapType.SecurityGroup && !string.IsNullOrEmpty(m.Value))
            .Select(m => m.Value)
            .Distinct(StringComparer.OrdinalIgnoreCase)
            .ToList();
    }

    internal IEnumerable<Claim> MapApiRolesToClaims(List<ApiResourceRole> roles, string apiName, string? userObjectId, HashSet<string> userMembershipGroups)
    {
        if (roles == null || roles.Count == 0)
        {
            _logger.LogDebug("API Resource '{ApiResourceName}' doesn't have any roles", apiName);
            yield break;
        }

        foreach (var customRole in roles)
        {
            foreach (var claim in ProcessCustomRole(apiName, customRole, userObjectId, userMembershipGroups))
            {
                yield return claim;
            }
        }
    }

    internal IEnumerable<Claim> ProcessCustomRole(string apiName, ApiResourceRole customRole, string? userObjectId, HashSet<string> userMembershipGroups)
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

            if (HasMappingMatch(roleMapping, userObjectId, userMembershipGroups))
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

    internal static bool HasMappingMatch(RoleMapping roleMapping, string? userObjectId, HashSet<string> userMembershipGroups)
    {
        return roleMapping.MappingType switch
        {
            RoleMapType.SecurityGroup => userMembershipGroups.Contains(roleMapping.Value),
            RoleMapType.UserObjectId => string.Equals(userObjectId, roleMapping.Value, StringComparison.OrdinalIgnoreCase),
            _ => false
        };
    }
}
