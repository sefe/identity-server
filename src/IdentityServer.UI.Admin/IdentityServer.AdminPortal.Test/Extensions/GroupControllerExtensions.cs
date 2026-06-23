// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

using System.Security.Claims;
using Microsoft.AspNetCore.Mvc;
using IdentityServer.Abstraction.Entities.EntraEntities;
using IdentityServer.AdminPortal.Server.Controllers;
using IdentityServer.AdminPortal.Test.Controller;

namespace IdentityServer.AdminPortal.Test.Extensions;

internal static class GroupControllerExtensions
{
    public static async Task<GroupResponse> Call_GetGroupsByDisplayNameAsync(this GroupController controller, string searchString, string skipToken, ClaimsPrincipal user)
    {
        ControllerTestBase.SetControllerContext(controller, user);
        var result = await controller.GetGroupsByDisplayName(searchString, skipToken);
        var entity = ((OkObjectResult)result.Result!).Value as GroupResponse;
        return entity!;
    }
}
