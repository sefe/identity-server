// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

using System.Security.Claims;
using Microsoft.AspNetCore.Mvc;
using IdentityServer.Abstraction.DTO.Clients;
using IdentityServer.Abstraction.Entities.IdentityServerConfig;
using IdentityServer.AdminPortal.Server.Controllers;
using IdentityServer.AdminPortal.Test.Controller;

namespace IdentityServer.AdminPortal.Test.Extensions;

public static class ClientRoleMappingControllerExtensions
{
    public static ClientPropertyRoleMappingDtoCreate NewRoleMappingFor(int clientId, int roleId, ClientRoleMapType roleMapType, string value)
    {
        return new ClientPropertyRoleMappingDtoCreate
        {
            ClientId = clientId,
            ClientRoleId = roleId,
            MappingType = roleMapType,
            Value = value,
        };
    }

    public static async Task<ClientPropertyRoleMappingDtoRead> Call_AddClientRoleMappingAsync(
    this ClientPropertyRoleMappingController controller,
    ClientPropertyRoleMappingDtoCreate roleDtoCreate,
    ClaimsPrincipal user)
    {
        ControllerTestBase.SetControllerContext(controller, user);
        var response = ((OkObjectResult)(await controller.CreatePropertyAsync(roleDtoCreate)).Result).Value as ClientPropertyRoleMappingDtoRead;
        return response!;
    }

    public static async Task<int?> Call_DeleteClientRoleMappingAsync(
        this ClientPropertyRoleMappingController controller,
        int roleId,
        ClaimsPrincipal user)
    {
        ControllerTestBase.SetControllerContext(controller, user);
        var response = ((OkObjectResult)(await controller.DeletePropertyByIdAsync(roleId)).Result).Value as int?;
        return response!;
    }
}
