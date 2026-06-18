using System.Security.Claims;
using Microsoft.AspNetCore.Mvc;
using IdentityServer.Abstraction.DTO.ApiResources;
using IdentityServer.AdminPortal.Server.Controllers;
using IdentityServer.AdminPortal.Test.Controller;

namespace IdentityServer.AdminPortal.Test.Extensions;

internal static class ApiResourceSecretControllerExtensions
{
    public static readonly Func<ApiResourcePropertySecretDtoCreate> GetDefaultApiResourceSecret = () => new()
    {
        Description = "unitTestSecret1",
        ValidityPeriodYears = 2
    };

    public static readonly Func<int, ApiResourcePropertySecretDtoCreate> GetDefaultApiResourceSecretFor = apiResourceId =>
    {
        var secret = GetDefaultApiResourceSecret();
        secret.ApiResourceId = apiResourceId;
        return secret;
    };

    public static async Task<ApiResourcePropertySecretValueDtoRead> Call_CreateSecretAsync(
        this ApiResourcePropertySecretController controller, ApiResourcePropertySecretDtoCreate apiResourceSecret, ClaimsPrincipal user)
    {
        ControllerTestBase.SetControllerContext(controller, user);
        var result = await controller.CreatePropertyAsync(apiResourceSecret);
        var entity = ((OkObjectResult)result.Result).Value as ApiResourcePropertySecretValueDtoRead;
        return entity;
    }

    public static async Task<int> Call_DeleteSecretAsync(this ApiResourcePropertySecretController controller, int id, ClaimsPrincipal user)
    {
        ControllerTestBase.SetControllerContext(controller, user);
        var result = (int)((OkObjectResult)(await controller.DeletePropertyByIdAsync(id)).Result).Value;
        return result;
    }
}
