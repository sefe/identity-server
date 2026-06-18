using System.Security.Claims;

namespace IdentityServer.Services.ApiRoles;

public interface IApiUserRoleClaimMapper
{
    IAsyncEnumerable<Claim> ProcessApiRoleMappingsForUserAsync(IEnumerable<string> apiResourceNames, string userId);
}
