// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

using System.Security.Claims;
using Microsoft.AspNetCore.Mvc;
using IdentityServer.Abstraction.DTO.Clients;
using IdentityServer.AdminPortal.Server.Controllers;
using IdentityServer.AdminPortal.Test.Controller;

namespace IdentityServer.AdminPortal.Test.Extensions;

public static class ClientPostLogoutRedirectControllerExtensions
{
    public static async Task<ClientPropertyPostLogoutRedirectUriDtoRead> Call_AddClientPostLogoutRedirectAsync(
        this ClientPropertyPostLogoutRedirectController controller,
        int clientId,
        string postLogoutRedirectUri,
        ClaimsPrincipal user)
    {
        ControllerTestBase.SetControllerContext(controller, user);
        var postLogoutRedirectDto = new ClientPropertyPostLogoutRedirectUriDtoCreate
        {
            ClientId = clientId,
            PostLogoutRedirectUri = postLogoutRedirectUri
        };
        var response = ((OkObjectResult)(await controller.CreatePropertyAsync(postLogoutRedirectDto)).Result).Value as ClientPropertyPostLogoutRedirectUriDtoRead;
        return response!;
    }

    public static async Task<int?> Call_DeleteClientPostLogoutRedirectAsync(
        this ClientPropertyPostLogoutRedirectController controller,
        int postLogoutRedirectId,
        ClaimsPrincipal user)
    {
        ControllerTestBase.SetControllerContext(controller, user);
        var response = ((OkObjectResult)(await controller.DeletePropertyByIdAsync(postLogoutRedirectId)).Result).Value as int?;
        return response!;
    }

    public static void AssertClientPostLogoutRedirectIsValid(ClientPropertyPostLogoutRedirectUriDtoRead addedPostLogoutRedirect, int expectedClientId, string expectedPostLogoutRedirectUri)
    {
        using (Assert.EnterMultipleScope())
        {
            Assert.That(addedPostLogoutRedirect.ClientId, Is.EqualTo(expectedClientId), "Client ID does not match.");
            Assert.That(addedPostLogoutRedirect.PostLogoutRedirectUri, Is.EqualTo(expectedPostLogoutRedirectUri), "Post-Logout Redirect URI does not match.");
        }
    }

    public static void AssertClientHasPostLogoutRedirectUri(ClientDtoRead client, string expectedPostLogoutRedirectUri)
    {
        Assert.That(client.PostLogoutRedirectUris.Any(r => r.PostLogoutRedirectUri == expectedPostLogoutRedirectUri), Is.True,
            $"Client does not have the expected Post-Logout Redirect URI: {expectedPostLogoutRedirectUri}");
    }

    public static void AssertClientDoesNotHavePostLogoutRedirectUri(ClientDtoRead client, string unexpectedPostLogoutRedirectUri)
    {
        Assert.That(client.PostLogoutRedirectUris.Any(r => r.PostLogoutRedirectUri == unexpectedPostLogoutRedirectUri), Is.False,
            $"Client should not have the Post-Logout Redirect URI: {unexpectedPostLogoutRedirectUri}");
    }
}
