// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

using System.Security.Claims;
using Microsoft.AspNetCore.Mvc;
using IdentityServer.Abstraction.DTO.Clients;
using IdentityServer.AdminPortal.Server.Controllers;
using IdentityServer.AdminPortal.Test.Controller;

namespace IdentityServer.AdminPortal.Test.Extensions;

public static class ClientRoleControllerExtensions
{
    public static ClientPropertyRoleDtoCreate NewRoleFor(int clientId, string roleName)
    {
        return new ClientPropertyRoleDtoCreate
        {
            ClientId = clientId,
            RoleName = roleName,
        };
    }

    public static async Task<ClientPropertyRoleDtoRead> Call_AddClientRoleAsync(
        this ClientPropertyRoleController controller,
        int ClientId,
        string roleName,
        ClaimsPrincipal user)
    {
        ControllerTestBase.SetControllerContext(controller, user);
        var createDto = new ClientPropertyRoleDtoCreate
        {
            ClientId = ClientId,
            RoleName = roleName
        };
        var response = ((OkObjectResult)(await controller.CreatePropertyAsync(createDto)).Result).Value as ClientPropertyRoleDtoRead;
        return response!;
    }

    public static async Task<ClientPropertyRoleDtoRead> Call_AddClientRoleAsync(
    this ClientPropertyRoleController controller,
    ClientPropertyRoleDtoCreate roleDtoCreate,
    ClaimsPrincipal user)
    {
        ControllerTestBase.SetControllerContext(controller, user);
        var response = ((OkObjectResult)(await controller.CreatePropertyAsync(roleDtoCreate)).Result).Value as ClientPropertyRoleDtoRead;
        return response!;
    }

    public static async Task<int?> Call_DeleteClientRoleAsync(
        this ClientPropertyRoleController controller,
        int roleId,
        ClaimsPrincipal user)
    {
        ControllerTestBase.SetControllerContext(controller, user);
        var response = ((OkObjectResult)(await controller.DeletePropertyByIdAsync(roleId)).Result).Value as int?;
        return response!;
    }
}
