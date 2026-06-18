using Microsoft.AspNetCore.Mvc;
using IdentityServer.Abstraction.Contracts;
using IdentityServer.Abstraction.DTO.ApiResources;

namespace IdentityServer.AdminPortal.Server.Controllers;

[Route("api/apiresource/secret")]
public class ApiResourcePropertySecretController : BasePropertyController<ApiResourcePropertySecretValueDtoRead, ApiResourcePropertySecretDtoCreate>
{
    public ApiResourcePropertySecretController(IDtoCreateRepository<ApiResourcePropertySecretValueDtoRead, ApiResourcePropertySecretDtoCreate> apiResourceSecretCreateRepository)
        : base(apiResourceSecretCreateRepository)
    {
    }
}
