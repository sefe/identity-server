using System.Security.Claims;
using Microsoft.AspNetCore.Mvc;
using IdentityServer.Abstraction.DTO.SystemPermissions;
using IdentityServer.AdminPortal.Server.Controllers;
using IdentityServer.AdminPortal.Test.Controller;

namespace IdentityServer.AdminPortal.Test.Extensions;

internal static class SystemPermissionRoleControllerExtensions
{
    public static async Task<SystemPermissionRoleDtoRead> Call_CreateSystemPermissionRoleAsync(
        this SystemPermissionRoleController controller, SystemPermissionRoleDtoCreate dto, ClaimsPrincipal user)
    {
        ControllerTestBase.SetControllerContext(controller, user);
        var result = await controller.CreateSystemPermissionRoleAsync(dto);
        var entity = ((OkObjectResult)result.Result).Value as SystemPermissionRoleDtoRead;
        return entity!;
    }

    public static async Task<SystemPermissionRoleDtoRead> Call_UpdateSystemPermissionRoleAsync(
        this SystemPermissionRoleController controller, SystemPermissionRoleDtoUpdate dto, ClaimsPrincipal user)
    {
        ControllerTestBase.SetControllerContext(controller, user);
        var result = await controller.UpdateSystemPermissionRoleAsync(dto);
        var entity = ((OkObjectResult)result.Result).Value as SystemPermissionRoleDtoRead;
        return entity!;
    }

    public static async Task<int?> Call_DeleteSystemPermissionRoleByIdAsync(
        this SystemPermissionRoleController controller, int roleId, ClaimsPrincipal user)
    {
        ControllerTestBase.SetControllerContext(controller, user);
        var result = await controller.DeleteSystemPermissionRoleByIdAsync(roleId);
        var entity = ((OkObjectResult)result.Result).Value as int?;
        return entity!;
    }
}
