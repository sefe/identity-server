using System.Security.Claims;
using Microsoft.AspNetCore.Mvc;
using IdentityServer.Abstraction.DTO.ApiResources;
using IdentityServer.AdminPortal.Server.Controllers;
using IdentityServer.AdminPortal.Test.Controller;

namespace IdentityServer.AdminPortal.Test.Extensions;

internal static class ApiResourceScopeControllerExtensions
{
    public static ApiResourcePropertyScopeDtoCreate NewScopeFor(int apiResourceId, string scopeName)
    {
        return new ApiResourcePropertyScopeDtoCreate
        {
            ApiResourceId = apiResourceId,
            Name = scopeName,
            DisplayName = scopeName,
        };
    }

    public static async Task<ApiResourcePropertyScopeDtoRead> Call_AddApiResourceScopeAsync(this ApiResourcePropertyScopeController controller, ApiResourcePropertyScopeDtoCreate dtoCreate, ClaimsPrincipal user)
    {
        ControllerTestBase.SetControllerContext(controller, user);
        var response = ((OkObjectResult)(await controller.CreatePropertyAsync(dtoCreate)).Result).Value as ApiResourcePropertyScopeDtoRead;
        return response!;
    }

    public static async Task<ApiResourcePropertyScopeDtoRead> Call_UpdateApiResourceScopeAsync(this ApiResourcePropertyScopeController controller, ApiResourcePropertyScopeDtoUpdate dtoUpdate, ClaimsPrincipal user)
    {
        ControllerTestBase.SetControllerContext(controller, user);
        var response = ((OkObjectResult)(await controller.UpdateApiResourceScopeAsync(dtoUpdate)).Result).Value as ApiResourcePropertyScopeDtoRead;
        return response!;
    }

    public static async Task<int?> Call_DeleteApiResourceScopeAsync(this ApiResourcePropertyScopeController controller, int apiResourceScopeId, ClaimsPrincipal user)
    {
        ControllerTestBase.SetControllerContext(controller, user);
        var response = ((OkObjectResult)(await controller.DeletePropertyByIdAsync(apiResourceScopeId)).Result).Value as int?;
        return response!;
    }

    public static void AssertApiResourceHasScope(ApiResourceDtoRead updatedApiResource, params string[] scopes)
    {
        using (Assert.EnterMultipleScope())
        {
            Assert.That(updatedApiResource.Scopes, Is.Not.Null);
            Assert.That(updatedApiResource.Scopes!, Has.Count.EqualTo(scopes.Length));
            foreach (var scope in scopes)
            {
                Assert.That(updatedApiResource.Scopes!.Any(x => x.Scope == scope), Is.True);
            }
            foreach (var scope in updatedApiResource.Scopes!)
            {
                Assert.That(scope.ApiResourceId, Is.EqualTo(updatedApiResource.Id));
            }
        }
    }

    public static void AssertApiResourceScopeHasApiScope(ApiResourcePropertyScopeDtoRead addedScope, string scope)
    {
        Assert.That(addedScope.ApiScope, Is.Not.Null);
        using (Assert.EnterMultipleScope())
        {
            Assert.That(addedScope.ApiScope.Id, Is.Not.Zero);
            Assert.That(addedScope.ApiScope.Name, Is.EqualTo(scope));
            Assert.That(addedScope.ApiScope.DisplayName, Is.EqualTo(scope));
            Assert.That(addedScope.ApiScope.Enabled, Is.True);
            Assert.That(addedScope.ApiScope.Required, Is.True);
        }
    }

    public static void AssertApiResourceScopeIsValid(ApiResourcePropertyScopeDtoRead addedScope, int apiResourceId, string scope)
    {
        Assert.That(addedScope, Is.Not.Null);
        using (Assert.EnterMultipleScope())
        {
            Assert.That(addedScope.Scope, Is.EqualTo(scope));
            Assert.That(addedScope.ApiResourceId, Is.EqualTo(apiResourceId));
        }
    }
}
