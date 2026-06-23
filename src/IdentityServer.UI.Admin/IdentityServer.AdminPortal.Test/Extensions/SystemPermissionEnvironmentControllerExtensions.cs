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

internal static class SystemPermissionEnvironmentControllerExtensions
{
    public static async Task<SystemPermissionDtoRead> Call_CreateSystemPermissionEnvironmentAsync(
        this SystemPermissionEnvironmentController controller, SystemPermissionEnvironmentDtoCreate envDto, ClaimsPrincipal user)
    {
        ControllerTestBase.SetControllerContext(controller, user);
        var result = await controller.CreateSystemPermissionEnvironmentAsync(envDto);
        var entity = ((OkObjectResult)result.Result).Value as SystemPermissionDtoRead;
        return entity!;
    }

    public static async Task<SystemPermissionEnvironmentDtoRead> Call_GetSystemPermissionEnvironmentByIdAsync(
        this SystemPermissionEnvironmentController controller, int envId, ClaimsPrincipal user)
    {
        ControllerTestBase.SetControllerContext(controller, user);
        var result = await controller.GetSystemPermissionEnvironmentByIdAsync(envId);
        var entity = ((OkObjectResult)result.Result).Value as SystemPermissionEnvironmentDtoRead;
        return entity!;
    }

    public static async Task<int?> Call_DeleteSystemPermissionEnvironmentByIdAsync(
        this SystemPermissionEnvironmentController controller, int envId, ClaimsPrincipal user)
    {
        ControllerTestBase.SetControllerContext(controller, user);
        var result = await controller.DeleteSystemPermissionEnvironmentByIdAsync(envId);
        var entity = ((OkObjectResult)result.Result).Value as int?;
        return entity!;
    }

    public static async Task<string[]> Call_GetSystemPermissionEnvironmentContactsByIdAsync(
        this SystemPermissionEnvironmentController controller, int envId, ClaimsPrincipal user)
    {
        ControllerTestBase.SetControllerContext(controller, user);
        var result = await controller.GetSystemPermissionEnvironmentContactsByIdAsync(envId);
        var entity = ((OkObjectResult)result.Result).Value as string[];
        return entity!;
    }

    public static async Task<DataEnvelope<SystemPermissionEnvironmentDtoRead>> Call_GetSystemPermissionEnvironmentsPagedAsync(
        this SystemPermissionEnvironmentController controller, DataSourceRequest req, ClaimsPrincipal user)
    {
        ControllerTestBase.SetControllerContext(controller, user);
        var result = await controller.GetSystemPermissionEnvironmentsPagedAsync(req);
        var entity = ((OkObjectResult)result.Result).Value as DataEnvelope<SystemPermissionEnvironmentDtoRead>;
        return entity!;
    }
}
