using System.Security.Claims;
using Microsoft.AspNetCore.Mvc;
using IdentityServer.Abstraction.DTO.Clients;
using IdentityServer.AdminPortal.Server.Controllers;
using IdentityServer.AdminPortal.Test.Controller;

namespace IdentityServer.AdminPortal.Test.Extensions;

public static class ClientGrantControllerExtensions
{
    public static async Task<ClientPropertyGrantDtoRead> Call_AddClientGrantAsync(
        this ClientPropertyGrantController controller,
        int clientId,
        string grantType,
        ClaimsPrincipal user)
    {
        ControllerTestBase.SetControllerContext(controller, user);
        var grantDto = new ClientPropertyGrantDtoCreate
        {
            ClientId = clientId,
            GrantType = grantType
        };
        var response = ((OkObjectResult)(await controller.CreatePropertyAsync(grantDto)).Result).Value as ClientPropertyGrantDtoRead;
        return response!;
    }

    public static async Task<int?> Call_DeleteClientGrantAsync(
        this ClientPropertyGrantController controller,
        int grantId,
        ClaimsPrincipal user)
    {
        ControllerTestBase.SetControllerContext(controller, user);
        var response = ((OkObjectResult)(await controller.DeletePropertyByIdAsync(grantId)).Result).Value as int?;
        return response!;
    }

    public static void AssertClientGrantIsValid(ClientPropertyGrantDtoRead addedGrant, int expectedClientId, string expectedGrantType)
    {
        using (Assert.EnterMultipleScope())
        {
            Assert.That(addedGrant.ClientId, Is.EqualTo(expectedClientId), "Client ID does not match.");
            Assert.That(addedGrant.GrantType, Is.EqualTo(expectedGrantType), "Grant type does not match.");
        }
    }

    public static void AssertClientHasGrantType(ClientDtoRead client, string expectedGrantType)
    {
        Assert.That(client.AllowedGrantTypes.Any(g => g.GrantType == expectedGrantType), Is.True,
            $"Client does not have the expected grant type: {expectedGrantType}");
    }

    public static void AssertClientDoesNotHaveGrantType(ClientDtoRead client, string unexpectedGrantType)
    {
        Assert.That(client.AllowedGrantTypes.Any(g => g.GrantType == unexpectedGrantType), Is.False,
            $"Client should not have the grant type: {unexpectedGrantType}");
    }
}
