using System.Security.Claims;

namespace IdentityServer.Services.ClientRoles;

public interface IClientUserRoleClaimMapper
{
    IAsyncEnumerable<Claim> ProcessClientRoleMappingsForUserAsync(string clientId, string userId);
}
