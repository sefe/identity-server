using Microsoft.AspNetCore.Mvc;
using IdentityServer.Abstraction.Contracts;
using IdentityServer.Abstraction.DTO.ApiResources;

namespace IdentityServer.AdminPortal.Server.Controllers;

[Route("api/apiresource/role")]
public class ApiResourcePropertyRoleController : BasePropertyController<ApiResourcePropertyRoleDtoRead, ApiResourcePropertyRoleDtoCreate>
{
    public ApiResourcePropertyRoleController(IDtoCreateRepository<ApiResourcePropertyRoleDtoRead, ApiResourcePropertyRoleDtoCreate> apiResourceRoleCreateRepository)
        : base(apiResourceRoleCreateRepository)
    {
    }
}
