// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

using System.Security.Claims;
using Microsoft.AspNetCore.Mvc;
using Telerik.DataSource;
using IdentityServer.Abstraction.DTO.SystemPermissions;
using IdentityServer.AdminPortal.Server.Controllers;
using IdentityServer.AdminPortal.Test.Controller;
using IdentityServer.AdminPortal.Web.Models;

namespace IdentityServer.AdminPortal.Test.Extensions;

internal static class SystemPermissionControllerExtensions
{
    public static SystemPermissionDtoCreate GetDefaultSystemPermission => new()
    {
        Name = Guid.NewGuid().ToString(),
        Description = "UnitSystemPermission1",
    };

    public static async Task<SystemPermissionDtoRead> Call_CreateSystemPermissionAsync(this SystemPermissionController controller, SystemPermissionDtoCreate systemPermission, ClaimsPrincipal user)
    {
        ControllerTestBase.SetControllerContext(controller, user);
        var result = await controller.CreateSystemPermissionAsync(systemPermission);
        var entity = ((OkObjectResult)result.Result).Value as SystemPermissionDtoRead;
        return entity!;
    }

    public static async Task<SystemPermissionDtoRead> Call_GetSystemPermissionByIdAsync(this SystemPermissionController controller, int systemPermissionId, ClaimsPrincipal user)
    {
        ControllerTestBase.SetControllerContext(controller, user);
        var result = await controller.GetSystemPermissionByIdAsync(systemPermissionId);
        var entity = ((OkObjectResult)result.Result).Value as SystemPermissionDtoRead;
        return entity!;
    }

    public static async Task<int?> Call_DeleteSystemPermissionByIdAsync(this SystemPermissionController controller, int systemPermissionId, ClaimsPrincipal user)
    {
        ControllerTestBase.SetControllerContext(controller, user);
        var result = await controller.DeleteSystemPermissionByIdAsync(systemPermissionId);
        var entity = ((OkObjectResult)result.Result).Value as int?;
        return entity!;
    }

    public static async Task<SystemPermissionDtoRead> Call_UpdateSystemPermissionAsync(this SystemPermissionController controller, SystemPermissionDtoUpdate systemPermission, ClaimsPrincipal user)
    {
        ControllerTestBase.SetControllerContext(controller, user);
        var result = await controller.UpdateSystemPermissionAsync(systemPermission);
        var entity = ((OkObjectResult)result.Result).Value as SystemPermissionDtoRead;
        return entity!;
    }

    public static async Task<List<SystemPermissionShortDtoRead>> Call_GetSystemPermissionsPagedAsync(this SystemPermissionController controller, ClaimsPrincipal user)
    {
        var req = new DataSourceRequest()
        {
            Page = 1,
            PageSize = 10
        };
        ControllerTestBase.SetControllerContext(controller, user);
        var result = await controller.GetSystemPermissionsPagedAsync(req);
        var entity = ((OkObjectResult)result.Result).Value as DataEnvelope<SystemPermissionShortDtoRead>;
        return entity!.CurrentPageData;
    }
}
