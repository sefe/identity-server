// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

using System.Security.Claims;
using Microsoft.AspNetCore.Mvc;
using IdentityServer.Abstraction.DTO.Clients;
using IdentityServer.AdminPortal.Server.Controllers;
using IdentityServer.AdminPortal.Test.Controller;

namespace IdentityServer.AdminPortal.Test.Extensions;

public static class ClientEntraAppControllerExtensions
{
    public static async Task<ClientPropertyEntraAppDtoRead> Call_AddClientEntraAppAsync(
        this ClientPropertyEntraAppController controller,
        int clientId,
        string appId,
        ClaimsPrincipal user)
    {
        ControllerTestBase.SetControllerContext(controller, user);
        var entraAppDto = new ClientPropertyEntraAppDtoCreate
        {
            ClientId = clientId,
            AppId = appId
        };
        var response = ((OkObjectResult)(await controller.CreatePropertyAsync(entraAppDto)).Result).Value as ClientPropertyEntraAppDtoRead;
        return response!;
    }

    public static async Task<int?> Call_DeleteClientEntraAppAsync(
        this ClientPropertyEntraAppController controller,
        int entraAppId,
        ClaimsPrincipal user)
    {
        ControllerTestBase.SetControllerContext(controller, user);
        var response = ((OkObjectResult)(await controller.DeletePropertyByIdAsync(entraAppId)).Result).Value as int?;
        return response!;
    }

    public static void AssertClientEntraAppIsValid(ClientPropertyEntraAppDtoRead addedEntraApp, int expectedClientId, string expectedAppId)
    {
        using (Assert.EnterMultipleScope())
        {
            Assert.That(addedEntraApp.ClientId, Is.EqualTo(expectedClientId), "Client ID does not match.");
            Assert.That(addedEntraApp.AppId, Is.EqualTo(expectedAppId), "AppId does not match.");
        }
    }

    public static void AssertClientHasEntraApp(ClientDtoRead client, string expectedAppId)
    {
        Assert.That(client.EntraApps.Any(ea => ea.AppId == expectedAppId), Is.True,
            $"Client does not have the expected Entra AppId: {expectedAppId}");
    }

    public static void AssertClientDoesNotHaveEntraApp(ClientDtoRead client, string unexpectedAppId)
    {
        Assert.That(client.EntraApps.Any(ea => ea.AppId == unexpectedAppId), Is.False,
            $"Client should not have the Entra AppId: {unexpectedAppId}");
    }
}
