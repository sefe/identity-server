using System.Security.Claims;
using Microsoft.AspNetCore.Mvc;
using IdentityServer.Abstraction.DTO.ApiResources;
using IdentityServer.Abstraction.DTO.Clients;
using IdentityServer.AdminPortal.Server.Controllers;
using IdentityServer.AdminPortal.Test.Controller;

namespace IdentityServer.AdminPortal.Test.Extensions;

internal static class ClientScopeControllerExtensions
{
    public static async Task<ClientPropertyScopeDtoRead> Call_AddClientScopeAsync(this ClientPropertyScopeController controller, int clientId, string scope, ClaimsPrincipal user)
    {
        var dtoCreate = new ClientPropertyScopeDtoCreate
        {
            ClientId = clientId,
            Scope = scope,
        };
        ControllerTestBase.SetControllerContext(controller, user);
        var response = ((OkObjectResult)(await controller.CreatePropertyAsync(dtoCreate)).Result).Value as ClientPropertyScopeDtoRead;
        return response!;
    }

    public static async Task<int?> Call_DeleteClientScopeAsync(this ClientPropertyScopeController controller, int clientScopeId, ClaimsPrincipal user)
    {
        ControllerTestBase.SetControllerContext(controller, user);
        var response = ((OkObjectResult)(await controller.DeletePropertyByIdAsync(clientScopeId)).Result).Value as int?;
        return response!;
    }

    public static void AssertClientHasScope(ClientDtoRead updatedClient, params string[] scopes)
    {
        using (Assert.EnterMultipleScope())
        {
            Assert.That(updatedClient.AllowedScopes, Is.Not.Null);
            Assert.That(updatedClient.AllowedScopes!, Has.Count.EqualTo(scopes.Length));
            foreach (var scope in scopes)
            {
                Assert.That(updatedClient.AllowedScopes!.Any(x => x.Scope == scope), Is.True);
            }
            foreach (var scope in updatedClient.AllowedScopes!)
            {
                Assert.That(scope.ClientId, Is.EqualTo(updatedClient.Id));
            }
        }
    }

    public static void AssertClientScopeHasApiScope(ClientPropertyScopeDtoRead addedScope, ApiResourcePropertyScopeDtoCreate scopeDto)
    {
        Assert.That(addedScope.ApiScope, Is.Not.Null);
        using (Assert.EnterMultipleScope())
        {
            Assert.That(addedScope.ApiScope.Id, Is.Not.Zero);
            Assert.That(addedScope.ApiScope.Name, Is.EqualTo(scopeDto.Name));
            Assert.That(addedScope.ApiScope.DisplayName, Is.EqualTo(scopeDto.DisplayName));
            Assert.That(addedScope.ApiScope.Enabled, Is.EqualTo(scopeDto.Enabled));
            Assert.That(addedScope.ApiScope.Required, Is.EqualTo(scopeDto.Required));
        }
    }

    public static void AssertClientScopeIsValid(ClientPropertyScopeDtoRead addedScope, int clientId, string scope)
    {
        Assert.That(addedScope, Is.Not.Null);
        using (Assert.EnterMultipleScope())
        {
            Assert.That(addedScope.Scope, Is.EqualTo(scope));
            Assert.That(addedScope.ClientId, Is.EqualTo(clientId));
        }
    }
}
