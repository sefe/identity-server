// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

using System.Security.Claims;
using Microsoft.AspNetCore.Mvc;
using IdentityServer.Abstraction.DTO.Import;
using IdentityServer.AdminPortal.Server.Controllers;
using IdentityServer.AdminPortal.Test.Controller;

namespace IdentityServer.AdminPortal.Test.Extensions;

public static class ClientImportControllerExtensions
{
    public static ClientRoleImportDto NewImportDto()
    {
        return new ClientRoleImportDto
        {
            ImportStrategy = ImportStrategy.Replace,
            Roles = new List<Abstraction.DTO.Export.RoleValueObject<Abstraction.DTO.Export.ClientRoleMappingValueObject>>()
        };
    }

    public static async Task<OperationStatus> Call_ImportClientRolesAsync(
        this ClientImportController controller,
        int clientId,
        ClientRoleImportDto importDto,
        ClaimsPrincipal user)
    {
        ControllerTestBase.SetControllerContext(controller, user);
        var result = await controller.ImportClientRoles(clientId, importDto);
        var entity = ((OkObjectResult)result.Result).Value as OperationStatus;
        return entity!;
    }

    public static async Task<OperationStatus> Call_ValidateImportClientRolesAsync(
        this ClientImportController controller,
        int clientId,
        ClientRoleImportDto importDto,
        ClaimsPrincipal user)
    {
        ControllerTestBase.SetControllerContext(controller, user);
        var result = await controller.ValidateImportClientRoles(clientId, importDto);
        var entity = ((OkObjectResult)result.Result).Value as OperationStatus;
        return entity!;
    }
}
