using Microsoft.AspNetCore.Mvc;
using IdentityServer.Abstraction.Contracts;
using IdentityServer.Abstraction.DTO.ApiResources;

namespace IdentityServer.AdminPortal.Server.Controllers;

[Route("api/apiresource/rolemapping")]
public class ApiResourcePropertyRoleMappingController : BasePropertyController<ApiResourcePropertyRoleMappingDtoRead, ApiResourcePropertyRoleMappingDtoCreate>
{
    public ApiResourcePropertyRoleMappingController(IDtoCreateRepository<ApiResourcePropertyRoleMappingDtoRead, ApiResourcePropertyRoleMappingDtoCreate> apiResourceRoleMappingCreateRepository)
        : base(apiResourceRoleMappingCreateRepository)
    {
    }
}
