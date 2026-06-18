using System.Security.Claims;
using Microsoft.AspNetCore.Mvc;
using IdentityServer.Abstraction.Entities.EntraEntities;
using IdentityServer.AdminPortal.Server.Controllers;
using IdentityServer.AdminPortal.Test.Controller;

namespace IdentityServer.AdminPortal.Test.Extensions;

internal static class UserControllerExtensions
{
    public static async Task<UserResponse> Call_GetUserByIdAsync(this UserController controller, string userId, ClaimsPrincipal user)
    {
        ControllerTestBase.SetControllerContext(controller, user);
        var result = await controller.GetUserById(userId);
        var entity = ((OkObjectResult)result.Result!).Value as UserResponse;
        return entity!;
    }

    public static async Task<UserResponse> Call_SearchUsersByDisplayNameAsync(this UserController controller, string searchString, ClaimsPrincipal user)
    {
        ControllerTestBase.SetControllerContext(controller, user);
        var result = await controller.SearchUsersByDisplayName(searchString);
        var entity = ((OkObjectResult)result.Result!).Value as UserResponse;
        return entity!;
    }

    //public static async Task<BadRequestObjectResult> Call_SearchUsersByDisplayNameBadRequestAsync(this UserController controller, string searchString, ClaimsPrincipal user)
    //{
    //    ControllerTestBase.SetControllerContext(controller, user);
    //    var result = await controller.SearchUsersByDisplayName(searchString);
    //    return (BadRequestObjectResult)result.Result!;
    //}
}
