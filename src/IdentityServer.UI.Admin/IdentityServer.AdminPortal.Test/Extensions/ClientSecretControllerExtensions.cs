// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

using System.Security.Claims;
using Microsoft.AspNetCore.Mvc;
using IdentityServer.Abstraction.DTO.Clients;
using IdentityServer.AdminPortal.Server.Controllers;
using IdentityServer.AdminPortal.Test.Controller;

namespace IdentityServer.AdminPortal.Test.Extensions;

internal static class ClientSecretControllerExtensions
{
    public static readonly Func<ClientPropertySecretDtoCreate> GetDefaultClientSecret = () => new()
    {
        Description = "unitTestSecret1",
        ValidityPeriodYears = 2
    };

    public static readonly Func<int, ClientPropertySecretDtoCreate> GetDefaultClientSecretFor = clientId =>
    {
        var secret = GetDefaultClientSecret();
        secret.ClientId = clientId;
        return secret;
    };

    public static async Task<ClientPropertySecretValueDtoRead> Call_CreateSecretAsync(
        this ClientPropertySecretController controller, ClientPropertySecretDtoCreate clientSecret, ClaimsPrincipal user)
    {
        ControllerTestBase.SetControllerContext(controller, user);
        var result = await controller.CreatePropertyAsync(clientSecret);
        var entity = ((OkObjectResult)result.Result).Value as ClientPropertySecretValueDtoRead;
        return entity;
    }

    public static async Task<int> Call_DeleteSecretAsync(this ClientPropertySecretController controller, int id, ClaimsPrincipal user)
    {
        ControllerTestBase.SetControllerContext(controller, user);
        var result = (int)((OkObjectResult)(await controller.DeletePropertyByIdAsync(id)).Result).Value;
        return result;
    }
}
