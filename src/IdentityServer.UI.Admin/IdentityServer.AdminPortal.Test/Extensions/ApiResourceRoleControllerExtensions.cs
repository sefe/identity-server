// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

using System.Security.Claims;
using Microsoft.AspNetCore.Mvc;
using IdentityServer.Abstraction.DTO.ApiResources;
using IdentityServer.AdminPortal.Server.Controllers;
using IdentityServer.AdminPortal.Test.Controller;

namespace IdentityServer.AdminPortal.Test.Extensions;

public static class ApiResourceRoleControllerExtensions
{
    public static ApiResourcePropertyRoleDtoCreate NewRoleFor(int apiResourceId, string roleName)
    {
        return new ApiResourcePropertyRoleDtoCreate
        {
            ApiResourceId = apiResourceId,
            RoleName = roleName,
        };
    }

    public static async Task<ApiResourcePropertyRoleDtoRead> Call_AddApiResourceRoleAsync(
        this ApiResourcePropertyRoleController controller,
        int apiResourceId,
        string roleName,
        ClaimsPrincipal user)
    {
        ControllerTestBase.SetControllerContext(controller, user);
        var createDto = new ApiResourcePropertyRoleDtoCreate
        {
            ApiResourceId = apiResourceId,
            RoleName = roleName
        };
        var response = ((OkObjectResult)(await controller.CreatePropertyAsync(createDto)).Result).Value as ApiResourcePropertyRoleDtoRead;
        return response!;
    }

    public static async Task<ApiResourcePropertyRoleDtoRead> Call_AddApiResourceRoleAsync(
    this ApiResourcePropertyRoleController controller,
    ApiResourcePropertyRoleDtoCreate roleDtoCreate,
    ClaimsPrincipal user)
    {
        ControllerTestBase.SetControllerContext(controller, user);
        var response = ((OkObjectResult)(await controller.CreatePropertyAsync(roleDtoCreate)).Result).Value as ApiResourcePropertyRoleDtoRead;
        return response!;
    }

    public static async Task<int?> Call_DeleteApiResourceRoleAsync(
        this ApiResourcePropertyRoleController controller,
        int roleId,
        ClaimsPrincipal user)
    {
        ControllerTestBase.SetControllerContext(controller, user);
        var response = ((OkObjectResult)(await controller.DeletePropertyByIdAsync(roleId)).Result).Value as int?;
        return response!;
    }
}
