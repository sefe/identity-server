using System.Security.Claims;
using Microsoft.AspNetCore.Mvc;
using Telerik.DataSource;
using IdentityServer.Abstraction.DTO.ApiResources;
using IdentityServer.AdminPortal.Server.Controllers;
using IdentityServer.AdminPortal.Test.Controller;
using IdentityServer.AdminPortal.Web.Models;

namespace IdentityServer.AdminPortal.Test.Extensions;

internal static class ApiResourceControllerExtensions
{
    public static Func<int, ApiResourceDtoCreate> GetDefaultApiResource => envId => new()
    {
        Name = Guid.NewGuid().ToString(),
        DisplayName = "UnitApiResource1",
        SystemPermissionEnvironmentId = envId
    };

    public static async Task<ApiResourceDtoRead> Call_CreateApiResourceAsync(this ApiResourceController controller, ApiResourceDtoCreate apiResource, ClaimsPrincipal user)
    {
        ControllerTestBase.SetControllerContext(controller, user);
        var result = await controller.CreateApiResourceAsync(apiResource);
        var entity = ((OkObjectResult)result.Result).Value as ApiResourceDtoRead;
        return entity!;
    }

    public static async Task<ApiResourceDtoRead> Call_CloneApiResourceAsync(this ApiResourceController controller, ApiResourceDtoClone apiResource, ClaimsPrincipal user)
    {
        ControllerTestBase.SetControllerContext(controller, user);
        var result = await controller.CloneApiResourceAsync(apiResource);
        var entity = ((OkObjectResult)result.Result).Value as ApiResourceDtoRead;
        return entity!;
    }

    public static async Task<ApiResourceDtoRead> Call_GetApiResourceAsync(this ApiResourceController controller, int apiResourceId, ClaimsPrincipal user)
    {
        ControllerTestBase.SetControllerContext(controller, user);
        var result = await controller.GetApiResourceByIdAsync(apiResourceId);
        var entity = ((OkObjectResult)result.Result).Value as ApiResourceDtoRead;
        return entity!;
    }

    public static async Task<List<ApiResourceShortDtoRead>> Call_GetApiResourcesPagedAsync(this ApiResourceController controller, ClaimsPrincipal user)
    {
        var req = new DataSourceRequest()
        {
            Page = 1,
            PageSize = 10
        };
        ControllerTestBase.SetControllerContext(controller, user);
        var result = await controller.GetApiResourcesPagedAsync(req);
        var entity = ((OkObjectResult)result.Result).Value as DataEnvelope<ApiResourceShortDtoRead>;
        return entity!.CurrentPageData;
    }

    public static async Task<int?> Call_DeleteApiResourceAsync(this ApiResourceController controller, int apiResourceId, ClaimsPrincipal user)
    {
        ControllerTestBase.SetControllerContext(controller, user);
        var result = await controller.DeleteApiResourceByIdAsync(apiResourceId);
        var entity = ((OkObjectResult)result.Result).Value as int?;
        return entity!;
    }

    public static async Task<ApiResourceDtoRead> Call_UpdateApiResourceAsync(this ApiResourceController controller, ApiResourceDtoUpdate apiResource, ClaimsPrincipal user)
    {
        ControllerTestBase.SetControllerContext(controller, user);
        var result = await controller.UpdateApiResourceAsync(apiResource);
        var entity = ((OkObjectResult)result.Result).Value as ApiResourceDtoRead;
        return entity!;
    }
}
