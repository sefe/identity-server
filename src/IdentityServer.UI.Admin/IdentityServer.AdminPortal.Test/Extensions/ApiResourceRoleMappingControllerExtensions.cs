using System.Security.Claims;
using Microsoft.AspNetCore.Mvc;
using IdentityServer.Abstraction.DTO.ApiResources;
using IdentityServer.Abstraction.Entities.IdentityServerConfig;
using IdentityServer.AdminPortal.Server.Controllers;
using IdentityServer.AdminPortal.Test.Controller;

namespace IdentityServer.AdminPortal.Test.Extensions;

public static class ApiResourceRoleMappingControllerExtensions
{
    public static ApiResourcePropertyRoleMappingDtoCreate NewRoleMappingFor(int apiResourceId, int roleId, RoleMapType roleMapType, string value)
    {
        return new ApiResourcePropertyRoleMappingDtoCreate
        {
            ApiResourceId = apiResourceId,
            ApiResourceRoleId = roleId,
            MappingType = roleMapType,
            Value = value,
        };
    }

    public static async Task<ApiResourcePropertyRoleMappingDtoRead> Call_AddApiResourceRoleMappingAsync(
    this ApiResourcePropertyRoleMappingController controller,
    ApiResourcePropertyRoleMappingDtoCreate roleDtoCreate,
    ClaimsPrincipal user)
    {
        ControllerTestBase.SetControllerContext(controller, user);
        var response = ((OkObjectResult)(await controller.CreatePropertyAsync(roleDtoCreate)).Result).Value as ApiResourcePropertyRoleMappingDtoRead;
        return response!;
    }

    public static async Task<int?> Call_DeleteApiResourceRoleMappingAsync(
        this ApiResourcePropertyRoleMappingController controller,
        int roleId,
        ClaimsPrincipal user)
    {
        ControllerTestBase.SetControllerContext(controller, user);
        var response = ((OkObjectResult)(await controller.DeletePropertyByIdAsync(roleId)).Result).Value as int?;
        return response!;
    }
}
