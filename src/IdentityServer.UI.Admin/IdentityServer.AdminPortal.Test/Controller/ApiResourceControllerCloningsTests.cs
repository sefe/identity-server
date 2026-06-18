using Microsoft.Extensions.DependencyInjection;
using IdentityServer.Abstraction.DTO.ApiResources;
using IdentityServer.Abstraction.Entities.IdentityServerConfig.SystemPermissions;
using IdentityServer.Abstraction.Exceptions;
using IdentityServer.AdminPortal.Server.Controllers;
using IdentityServer.AdminPortal.Test.Extensions;
using IdentityServer.Tests.Common;

namespace IdentityServer.AdminPortal.Test.Controller;

public class ApiResourceControllerCloningsTests : ControllerTestBase
{
    private ApiResourceController _apiResourceController;
    private ApiResourcePropertyScopeController _apiResourceScopeController;
    private ApiResourcePropertySecretController _apiResourceSecretController;
    private ApiResourcePropertyRoleController _apiResourceRoleController;

    [SetUp]
    public async Task Setup()
    {
        var provider = IoC.GetProvider(sc =>
        {
            sc.AddScoped<ApiResourceController>();
            sc.AddScoped<ApiResourcePropertyScopeController>();
            sc.AddScoped<ApiResourcePropertySecretController>();
            sc.AddScoped<ApiResourcePropertyRoleController>();
            sc.ReplaceWithInstance(EverythingIsAllowed);
        });

        await Setup(provider);

        _apiResourceController = provider.GetRequiredService<ApiResourceController>();
        _apiResourceScopeController = provider.GetRequiredService<ApiResourcePropertyScopeController>();
        _apiResourceSecretController = provider.GetRequiredService<ApiResourcePropertySecretController>();
        _apiResourceRoleController = provider.GetRequiredService<ApiResourcePropertyRoleController>();
    }

    [Test]
    public async Task CloneApiResource_ClonesTopLevelProperties()
    {
        // Arrange
        var originalApiResource = await _apiResourceController.Call_CreateApiResourceAsync(
            ApiResourceControllerExtensions.GetDefaultApiResource(1), Admin);

        var cloneRequest = new ApiResourceDtoClone
        {
            Id = originalApiResource.Id,
            Name = "cloned-apiResource-id",
            DisplayName = "Cloned ApiResource",
            SystemPermissionEnvironmentId = originalApiResource.SystemPermissionEnvironmentId
        };

        // Act
        var clonedApiResource = await _apiResourceController.Call_CloneApiResourceAsync(cloneRequest, Admin);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(clonedApiResource.Id, Is.Not.EqualTo(originalApiResource.Id));
            Assert.That(clonedApiResource.Name, Is.EqualTo(cloneRequest.Name));
            Assert.That(clonedApiResource.DisplayName, Is.EqualTo(cloneRequest.DisplayName));
            Assert.That(clonedApiResource.SystemPermissionEnvironmentId, Is.EqualTo(originalApiResource.SystemPermissionEnvironmentId));
            Assert.That(clonedApiResource.AccessLevel, Is.EqualTo(SystemPermissionRoleType.Writer));
        }
    }

    [Test]
    public async Task CloneApiResource_ClonesRoles()
    {
        // Arrange
        var originalApiResource = await _apiResourceController.Call_CreateApiResourceAsync(ApiResourceControllerExtensions.GetDefaultApiResource(1), Admin);
        var role1 = await _apiResourceRoleController.Call_AddApiResourceRoleAsync(originalApiResource.Id, "role1", Admin);
        var role2 = await _apiResourceRoleController.Call_AddApiResourceRoleAsync(originalApiResource.Id, "role2", Admin);
        var cloneRequest = new ApiResourceDtoClone
        {
            Id = originalApiResource.Id,
            Name = "cloned-apiResource-id",
            DisplayName = "Cloned ApiResource",
            SystemPermissionEnvironmentId = originalApiResource.SystemPermissionEnvironmentId
        };

        // Act
        var clonedApiResource = await _apiResourceController.Call_CloneApiResourceAsync(cloneRequest, Admin);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(clonedApiResource.Roles, Has.Count.EqualTo(2));
            Assert.That(clonedApiResource.Roles[0].RoleName, Is.EqualTo(role1.RoleName));
            Assert.That(clonedApiResource.Roles[1].RoleName, Is.EqualTo(role2.RoleName));

        }
    }

    [Test]
    public void CloneApiResource_WithInvalidId_Fails()
    {
        // Arrange
        var cloneRequest = new ApiResourceDtoClone
        {
            Id = -1, // Invalid ID
            Name = "api-resource",
            DisplayName = "api-resource",
            SystemPermissionEnvironmentId = 1
        };

        // Act & Assert
        Assert.ThrowsAsync<EntityNotFoundException>(() => _apiResourceController.Call_CloneApiResourceAsync(cloneRequest, Admin));
    }

    [Test]
    public void CloneApiResource_WithExistingName_Fails()
    {
        // Arrange
        var originalApiResource = _apiResourceController.Call_CreateApiResourceAsync(
            ApiResourceControllerExtensions.GetDefaultApiResource(1), Admin).Result;

        var cloneRequest = new ApiResourceDtoClone
        {
            Id = originalApiResource.Id,
            Name = originalApiResource.Name, // Duplicate Name
            DisplayName = "Duplicate ApiResource",
            SystemPermissionEnvironmentId = originalApiResource.SystemPermissionEnvironmentId
        };

        // Act & Assert
        Assert.ThrowsAsync<EntityAlreadyExistsException>(() => _apiResourceController.Call_CloneApiResourceAsync(cloneRequest, Admin));
    }

    [Test]
    public async Task CloneApiResource_RenamesScopes()
    {
        // Arrange
        var originalApiResource = await _apiResourceController.Call_CreateApiResourceAsync(
            ApiResourceControllerExtensions.GetDefaultApiResource(1), Admin);
        var originalScope1 = ApiResourceScopeControllerExtensions.NewScopeFor(originalApiResource.Id, "scope1");
        var originalScope2 = ApiResourceScopeControllerExtensions.NewScopeFor(originalApiResource.Id, "scope2");
        _ = await _apiResourceScopeController.Call_AddApiResourceScopeAsync(originalScope1, Admin);
        _ = await _apiResourceScopeController.Call_AddApiResourceScopeAsync(originalScope2, Admin);

        var cloneRequest = new ApiResourceDtoClone
        {
            Id = originalApiResource.Id,
            Name = "cloned-apiResource-id",
            DisplayName = "Cloned ApiResource",
            SystemPermissionEnvironmentId = 1
        };

        var expectedScope1 = $"{cloneRequest.Name}.scope1";
        var expectedScope2 = $"{cloneRequest.Name}.scope2";

        // Act
        var clonedApiResource = await _apiResourceController.Call_CloneApiResourceAsync(cloneRequest, Admin);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(clonedApiResource.Scopes, Has.Count.EqualTo(2));
            Assert.That(clonedApiResource.Scopes[0].Scope, Is.EqualTo(expectedScope1));
            Assert.That(clonedApiResource.Scopes[1].Scope, Is.EqualTo(expectedScope2));
        }
    }

    [Test]
    public async Task CloneApiResource_RemovesApiResourceSecrets()
    {
        // Arrange
        var originalApiResource = await _apiResourceController.Call_CreateApiResourceAsync(
            ApiResourceControllerExtensions.GetDefaultApiResource(1), Admin);

        _ = _apiResourceSecretController.Call_CreateSecretAsync(new() { ApiResourceId = originalApiResource.Id, Description = "test secret desc" }, Admin);

        var cloneRequest = new ApiResourceDtoClone
        {
            Id = originalApiResource.Id,
            Name = "cloned-apiResource-id",
            DisplayName = "Cloned ApiResource",
            SystemPermissionEnvironmentId = 1
        };

        // Act
        var clonedApiResource = await _apiResourceController.Call_CloneApiResourceAsync(cloneRequest, Admin);

        // Assert
        Assert.That(clonedApiResource.Secrets, Is.Null.Or.Empty, "ApiResourceSecrets should be null in the cloned apiResource.");
    }

}
