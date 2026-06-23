// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

using System.Security.Claims;
using Microsoft.AspNetCore.Mvc;
using IdentityServer.Abstraction.DTO.Clients;
using IdentityServer.AdminPortal.Server.Controllers;
using IdentityServer.AdminPortal.Test.Controller;

namespace IdentityServer.AdminPortal.Test.Extensions;

public static class ClientRedirectControllerExtensions
{
    public static async Task<ClientPropertyRedirectUriDtoRead> Call_AddClientRedirectAsync(
        this ClientPropertyRedirectController controller,
        int clientId,
        string redirectUri,
        ClaimsPrincipal user)
    {
        ControllerTestBase.SetControllerContext(controller, user);
        var redirectDto = new ClientPropertyRedirectUriDtoCreate
        {
            ClientId = clientId,
            RedirectUri = redirectUri
        };
        var response = ((OkObjectResult)(await controller.CreatePropertyAsync(redirectDto)).Result).Value as ClientPropertyRedirectUriDtoRead;
        return response!;
    }

    public static async Task<int?> Call_DeleteClientRedirectAsync(
        this ClientPropertyRedirectController controller,
        int redirectId,
        ClaimsPrincipal user)
    {
        ControllerTestBase.SetControllerContext(controller, user);
        var response = ((OkObjectResult)(await controller.DeletePropertyByIdAsync(redirectId)).Result).Value as int?;
        return response!;
    }

    public static void AssertClientRedirectIsValid(ClientPropertyRedirectUriDtoRead addedRedirect, int expectedClientId, string expectedRedirectUri)
    {
        using (Assert.EnterMultipleScope())
        {
            Assert.That(addedRedirect.ClientId, Is.EqualTo(expectedClientId), "Client ID does not match.");
            Assert.That(addedRedirect.RedirectUri, Is.EqualTo(expectedRedirectUri), "Redirect URI does not match.");
        }
    }

    public static void AssertClientHasRedirectUri(ClientDtoRead client, string expectedRedirectUri)
    {
        Assert.That(client.RedirectUris.Any(r => r.RedirectUri == expectedRedirectUri), Is.True,
            $"Client does not have the expected Redirect URI: {expectedRedirectUri}");
    }

    public static void AssertClientDoesNotHaveRedirectUri(ClientDtoRead client, string unexpectedRedirectUri)
    {
        Assert.That(client.RedirectUris.Any(r => r.RedirectUri == unexpectedRedirectUri), Is.False,
            $"Client should not have the Redirect URI: {unexpectedRedirectUri}");
    }
}
