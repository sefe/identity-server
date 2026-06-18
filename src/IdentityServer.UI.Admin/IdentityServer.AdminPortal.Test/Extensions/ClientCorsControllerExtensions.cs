using System.Security.Claims;
using Microsoft.AspNetCore.Mvc;
using IdentityServer.Abstraction.DTO.Clients;
using IdentityServer.AdminPortal.Server.Controllers;
using IdentityServer.AdminPortal.Test.Controller;

namespace IdentityServer.AdminPortal.Test.Extensions;

public static class ClientCorsControllerExtensions
{
    public static async Task<ClientPropertyCorsOriginDtoRead> Call_AddClientCorsAsync(
        this ClientPropertyCorsController controller,
        int clientId,
        string corsOrigin,
        ClaimsPrincipal user)
    {
        ControllerTestBase.SetControllerContext(controller, user);
        var corsDto = new ClientPropertyCorsOriginDtoCreate
        {
            ClientId = clientId,
            Origin = corsOrigin
        };
        var response = ((OkObjectResult)(await controller.CreatePropertyAsync(corsDto)).Result).Value as ClientPropertyCorsOriginDtoRead;
        return response!;
    }

    public static async Task<int?> Call_DeleteClientCorsAsync(
        this ClientPropertyCorsController controller,
        int corsId,
        ClaimsPrincipal user)
    {
        ControllerTestBase.SetControllerContext(controller, user);
        var response = ((OkObjectResult)(await controller.DeletePropertyByIdAsync(corsId)).Result).Value as int?;
        return response!;
    }

    public static void AssertClientCorsIsValid(ClientPropertyCorsOriginDtoRead addedCors, int expectedClientId, string expectedOrigin)
    {
        using (Assert.EnterMultipleScope())
        {
            Assert.That(addedCors.ClientId, Is.EqualTo(expectedClientId), "Client ID does not match.");
            Assert.That(addedCors.Origin, Is.EqualTo(expectedOrigin), "CORS origin does not match.");
        }
    }

    public static void AssertClientHasCorsOrigin(ClientDtoRead client, string expectedOrigin)
    {
        Assert.That(client.AllowedCorsOrigins.Any(c => c.Origin == expectedOrigin), Is.True,
            $"Client does not have the expected CORS origin: {expectedOrigin}");
    }

    public static void AssertClientDoesNotHaveCorsOrigin(ClientDtoRead client, string unexpectedOrigin)
    {
        Assert.That(client.AllowedCorsOrigins.Any(c => c.Origin == unexpectedOrigin), Is.False,
            $"Client should not have the CORS origin: {unexpectedOrigin}");
    }
}
