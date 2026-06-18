using System.Security.Claims;
using IdentityServer.Abstraction.Contracts;
using IdentityServer.Abstraction.Contracts.MicrosoftGraph;
using IdentityServer.Abstraction.Entities.IdentityServerConfig;
using IdentityServer.Data.DuendeEntityExtensions;
using IdentityServer.Data.Entities.Roles;
using static IdentityServer.Abstraction.Constants;

namespace IdentityServer.Services.ClientRoles;

public class ClientUserRoleClaimMapper : IClientUserRoleClaimMapper
{
    private readonly IStorage<ClientExt> _clientStorage;
    private readonly IEntraUserService _entraService;
    private readonly ILogger<ClientUserRoleClaimMapper> _logger;

    public ClientUserRoleClaimMapper(IStorage<ClientExt> clientStorage, IEntraUserService entraService, ILogger<ClientUserRoleClaimMapper> logger)
    {
        _clientStorage = clientStorage;
        _entraService = entraService;
        _logger = logger;
    }

    public async IAsyncEnumerable<Claim> ProcessClientRoleMappingsForUserAsync(string clientId, string userId)
    {
        var requestedClient = await _clientStorage.FirstOrDefaultAsync(x => x.ClientId == clientId);
        if (requestedClient == null)
        {
            _logger.LogWarning("Client not found by ID: '{ClientId}'", clientId);
            yield break;
        }

        if (requestedClient.Roles == null || requestedClient.Roles.Count == 0)
        {
            _logger.LogDebug("Client '{ClientId}' doesn't have any roles", clientId);
            yield break;
        }

        if (requestedClient.Roles.All(cr => cr.Mappings == null || cr.Mappings.Count == 0))
        {
            _logger.LogDebug("Client '{ClientId}' custom roles don't have any mappings", clientId);
            yield break;
        }

        List<string> groupIdsToCheck = GetSecurityGroupIdsFromRoleMappings(requestedClient);

        HashSet<string> userMembershipGroups = await GetUserMembershipInMappedGroupsAsync(userId, groupIdsToCheck);

        foreach (var mappedRoleClaim in MapClientRolesToClaims(requestedClient.Roles, clientId, userId, userMembershipGroups))
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

    internal static List<string> GetSecurityGroupIdsFromRoleMappings(ClientExt requestedClient)
    {
        return requestedClient.Roles
            .SelectMany(r => r.Mappings ?? Enumerable.Empty<ClientRoleMapping>())
            .Where(m => m != null && m.MappingType == ClientRoleMapType.SecurityGroup && !string.IsNullOrEmpty(m.Value))
            .Select(m => m.Value)
            .Distinct(StringComparer.OrdinalIgnoreCase)
            .ToList();
    }

    internal IEnumerable<Claim> MapClientRolesToClaims(List<ClientRole> roles, string clientId, string? userObjectId, HashSet<string> userMembershipGroups)
    {
        foreach (var customRole in roles)
        {
            foreach (var claim in ProcessCustomRole(customRole, clientId, userObjectId, userMembershipGroups))
            {
                yield return claim;
            }
        }
    }

    internal IEnumerable<Claim> ProcessCustomRole(ClientRole customRole, string clientId, string? userObjectId, HashSet<string> userMembershipGroups)
    {
        foreach (var roleMapping in customRole.Mappings)
        {
            if (!IsValidRoleMapping(clientId, customRole.RoleName, roleMapping))
            {
                continue;
            }

            if (HasMappingMatch(roleMapping, userObjectId, userMembershipGroups, clientId, customRole.RoleName))
            {
                yield return new Claim(ClaimNames.UserRole, customRole.RoleName);
            }
        }
    }

    internal bool IsValidRoleMapping(string clientId, string roleName, ClientRoleMapping? roleMapping)
    {
        if (roleMapping == null)
        {
            _logger.LogWarning("Client '{ClientId}' custom role '{RoleName}' has a null mapping", clientId, roleName);
            return false;
        }

        if (string.IsNullOrEmpty(roleMapping.Value))
        {
            _logger.LogWarning("Client '{ClientId}' custom role '{RoleName}' has an empty mapping value", clientId, roleName);
            return false;
        }

        return true;
    }

    internal bool HasMappingMatch(ClientRoleMapping roleMapping, string? userObjectId, HashSet<string> userMembershipGroups, string clientId, string roleName)
    {
        return roleMapping.MappingType switch
        {
            ClientRoleMapType.SecurityGroup => userMembershipGroups.Contains(roleMapping.Value),
            ClientRoleMapType.UserObjectId => string.Equals(userObjectId, roleMapping.Value, StringComparison.OrdinalIgnoreCase),
            _ => LogUnsupportedMappingType(roleMapping.MappingType, clientId, roleName)
        };
    }

    private bool LogUnsupportedMappingType(ClientRoleMapType mappingType, string clientId, string roleName)
    {
        _logger.LogWarning("Client '{ClientId}' custom role '{RoleName}' mapping type '{MappingType}' is not supported",
            clientId, roleName, mappingType);
        return false;
    }
}
