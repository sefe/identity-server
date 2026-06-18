using System.Security.Claims;

namespace IdentityServer.Services.ApiRoles;

public interface IApiClientRoleClaimMapper
{
    IAsyncEnumerable<Claim> ProcessApiRoleMappingsForClientIdAsync(IEnumerable<string> apiResourceNames, string clientId);
}
