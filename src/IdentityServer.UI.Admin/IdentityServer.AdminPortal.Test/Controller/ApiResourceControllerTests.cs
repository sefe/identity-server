// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

using System.Security.Claims;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Extensions.DependencyInjection;
using NSubstitute;
using IdentityServer.Abstraction.Contracts;
using IdentityServer.Abstraction.DTO.ApiResources;
using IdentityServer.Abstraction.Entities.IdentityServerConfig.SystemPermissions;
using IdentityServer.Abstraction.Exceptions;
using IdentityServer.AdminPortal.Server.Controllers;
using IdentityServer.AdminPortal.Test.Extensions;
using IdentityServer.Data.DuendeEntityExtensions;
using IdentityServer.Tests.Common;
using DataEntities = Duende.IdentityServer.EntityFramework.Entities;

namespace IdentityServer.AdminPortal.Test.Controller;

public class ApiResourceControllerTests : ControllerTestBase
{
    private ClientController _clientController;
    private ClientPropertyScopeController _clientPropertyScopeController;
    private ApiResourceController _apiResourceController;
    private ApiResourcePropertyScopeController _apiResourceScopeController;
    private IStorage<ApiScopeExt> _apiScopeStorage;

    private ICache<DataEntities.ApiResource> _apiCache;
    private IApiResourceAuditService _apiResourceAuditService;

    [SetUp]
    public async Task Setup()
    {
        _apiCache = Substitute.For<ICache<DataEntities.ApiResource>>();

        var provider = IoC.GetProvider(sc =>
        {
            sc.AddScoped<ClientController>();
            sc.AddScoped<ClientPropertyScopeController>();
            sc.AddScoped<ApiResourceController>();
            sc.AddScoped<ApiResourcePropertyScopeController>();
            sc.AddScoped<ApiResourcePropertySecretController>();
            sc.ReplaceWithInstance(EverythingIsAllowed);
            sc.ReplaceWithInstance(_apiCache);
        });

        await Setup(provider);

        _clientController = provider.GetRequiredService<ClientController>();
        _clientPropertyScopeController = provider.GetRequiredService<ClientPropertyScopeController>();
        _apiResourceController = provider.GetRequiredService<ApiResourceController>();
        _apiResourceScopeController = provider.GetRequiredService<ApiResourcePropertyScopeController>();
        _apiScopeStorage = provider.GetRequiredService<IStorage<ApiScopeExt>>();
        _apiResourceAuditService = provider.GetRequiredService<IApiResourceAuditService>();
    }

    [Test]
    public async Task CreateApiResourceAsync_WithValidApiResource_ReturnsCreatedApiResource()
    {
        // Act
        var createdApiResource = await _apiResourceController.Call_CreateApiResourceAsync(ApiResourceControllerExtensions.GetDefaultApiResource(1), Admin);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(createdApiResource.Id, Is.EqualTo(1));
            Assert.That(createdApiResource.Secrets, Has.Count.Zero);
            Assert.That(createdApiResource.AccessLevel, Is.EqualTo(SystemPermissionRoleType.Writer));
        }
    }

    [Test]
    public async Task CreateApiResourceAsync_WithDuplicateName_ThrowsEntityAlreadyExistsException()
    {
        // Arrange 
        var client = ApiResourceControllerExtensions.GetDefaultApiResource(1);
        _ = await _apiResourceController.Call_CreateApiResourceAsync(client, Admin);

        // Act & Assert
        Assert.ThrowsAsync<EntityAlreadyExistsException>(() => _apiResourceController.Call_CreateApiResourceAsync(client, Admin));
    }

    [Test]
    public async Task UpdateApiResourceAsync_WithApiScopes_ReturnsUpdatedApiResourceWithScopes()
    {
        // Arrange
        var createdApiResource = await _apiResourceController.Call_CreateApiResourceAsync(ApiResourceControllerExtensions.GetDefaultApiResource(1), Admin);
        _ = await _apiResourceScopeController.Call_AddApiResourceScopeAsync(
            ApiResourceScopeControllerExtensions.NewScopeFor(createdApiResource.Id, Guid.NewGuid().ToString()), Admin);

        var apiUpdate = new ApiResourceDtoUpdate
        {
            Id = createdApiResource.Id,
            Description = "UpdatedDescription",
        };

        // Act
        var updatedResource = await _apiResourceController.Call_UpdateApiResourceAsync(apiUpdate, Admin);

        // Assert
        Assert.That(updatedResource.Scopes[0].ApiScope, Is.Not.Null);
    }

    [TestCaseSource(nameof(UpdateApiResourceRequesterCases))]
    public async Task UpdateApiResourceAsync_IfValid_ReturnsRequester(ClaimsPrincipal principal)
    {
        // Arrange
        var createdApiResource = await _apiResourceController.Call_CreateApiResourceAsync(ApiResourceControllerExtensions.GetDefaultApiResource(1), Admin);
        var apiUpdate = new ApiResourceDtoUpdate
        {
            Id = createdApiResource.Id,
            Description = "UpdatedDescription",
        };

        // Act
        var updatedResource = await _apiResourceController.Call_UpdateApiResourceAsync(apiUpdate, principal);

        // Assert
        Assert.That(updatedResource.AccessLevel, Is.EqualTo(SystemPermissionRoleType.Writer));
    }

    private static IEnumerable<TestCaseData> UpdateApiResourceRequesterCases()
    {
        yield return new TestCaseData(Admin);
        yield return new TestCaseData(Contributor);
    }

    [Test]
    public async Task UpdateApiResourceAsync_InvalidatesApiResourceCache()
    {
        // Arrange
        var createdApiResource = await _apiResourceController.Call_CreateApiResourceAsync(ApiResourceControllerExtensions.GetDefaultApiResource(1), Admin);
        var apiUpdate = new ApiResourceDtoUpdate
        {
            Id = createdApiResource.Id,
            Description = "UpdatedDescription",
        };

        // Act
        await _apiResourceController.Call_UpdateApiResourceAsync(apiUpdate, Admin);

        // Assert
        await _apiCache.Received(1).RemoveAsync(createdApiResource.Name);
    }

    [TestCaseSource(nameof(GetByIdApiResourceRequesterCases))]
    public async Task GetApiResourceAsync_ReturnsRequester(ClaimsPrincipal principal)
    {
        // Arrange
        var createdApiResource = await _apiResourceController.Call_CreateApiResourceAsync(ApiResourceControllerExtensions.GetDefaultApiResource(1), Admin);

        // Act
        var resource = await _apiResourceController.Call_GetApiResourceAsync(createdApiResource.Id, principal);

        // Assert
        Assert.That(resource.AccessLevel, Is.EqualTo(SystemPermissionRoleType.Writer));
    }

    [Test]
    public async Task GetApiResourceAsync_ReturnsLastUpdatedTimestamp()
    {
        // Arrange
        var createdApiResource = await _apiResourceController.Call_CreateApiResourceAsync(ApiResourceControllerExtensions.GetDefaultApiResource(1), Admin);
        var ts = DateTime.UtcNow;
        _apiResourceAuditService.GetLastModifiedByIdAsync(createdApiResource.Id).Returns(new EntityLastModifiedData
        {
            Id = createdApiResource.Id,
            LastModified = ts,
            Reason = "Scope added"
        });

        // Act
        var resource = await _apiResourceController.Call_GetApiResourceAsync(createdApiResource.Id, Admin);

        // Assert
        Assert.That(resource.Updated, Is.EqualTo(ts));
    }

    private static IEnumerable<TestCaseData> GetByIdApiResourceRequesterCases()
    {
        yield return new TestCaseData(Admin);
        yield return new TestCaseData(Contributor);
        yield return new TestCaseData(Reader);
        yield return new TestCaseData(SuperUser);
    }

    [Test]
    public async Task GetApiResourceByIdAsync_WithInvalidId_ReturnsNotFound()
    {
        // Arrange
        SetControllerContext(_apiResourceController, Contributor);

        // Act
        var response = await _apiResourceController.GetApiResourceByIdAsync(9999);

        // Assert
        Assert.That(response.Result, Is.TypeOf<NotFoundResult>());
    }

    [Test]
    public async Task DeleteApiResourceAsync_WhenApiScopesAreInUse_ThrowsEntityReferenceException()
    {
        var createdApiResource = await _apiResourceController.Call_CreateApiResourceAsync(ApiResourceControllerExtensions.GetDefaultApiResource(1), Admin);
        var createdScope = await _apiResourceScopeController.Call_AddApiResourceScopeAsync(
            ApiResourceScopeControllerExtensions.NewScopeFor(createdApiResource.Id, Guid.NewGuid().ToString()), Admin);

        var createdClient = await _clientController.Call_CreateClientAsync(ClientControllerExtensions.GetDefaultClient(1), Admin);
        await _clientPropertyScopeController.Call_AddClientScopeAsync(createdClient.Id, createdScope.Scope, Admin);

        // Act
        Assert.ThrowsAsync<EntityReferenceException>(() => _apiResourceController.Call_DeleteApiResourceAsync(createdApiResource.Id, Admin));
    }

    [Test]
    public async Task DeleteApiResourceAsync_WithNestedEntities_ExecutesSuccessfullyAndDeletesAssociatedApiScopes()
    {
        // Arrange
        var createdApiResource = await _apiResourceController.Call_CreateApiResourceAsync(ApiResourceControllerExtensions.GetDefaultApiResource(1), Admin);
        var createdScope = await _apiResourceScopeController.Call_AddApiResourceScopeAsync(
            ApiResourceScopeControllerExtensions.NewScopeFor(createdApiResource.Id, Guid.NewGuid().ToString()), Admin);

        // Act
        var result = await _apiResourceController.Call_DeleteApiResourceAsync(createdApiResource.Id, Admin);

        // Assert
        Assert.That(result, Is.EqualTo(createdApiResource.Id));
        var response = await _apiResourceController.GetApiResourceByIdAsync(createdApiResource.Id);
        Assert.That(response.Result, Is.TypeOf<NotFoundResult>());

        // Verify that the associated ApiScope entity is also deleted
        var scopeAfterDeletion = await _apiScopeStorage.FirstOrDefaultAsync(_ => _.Name == createdScope.Scope);
        Assert.That(scopeAfterDeletion, Is.Null);
    }

    [Test]
    public async Task DeleteApiResourceAsync_InvalidatesCache()
    {
        // Arrange
        var createdApiResource = await _apiResourceController.Call_CreateApiResourceAsync(ApiResourceControllerExtensions.GetDefaultApiResource(1), Admin);

        // Act
        await _apiResourceController.Call_DeleteApiResourceAsync(createdApiResource.Id, Admin);

        // Assert
        await _apiCache.Received(1).RemoveAsync(createdApiResource.Name);
    }

    [Test]
    public async Task GetApiResourcesPagedAsync_WithoutAuditData_ReturnsResourcesWithOriginalUpdatedValue()
    {
        // Arrange
        var createdApiResource1 = await _apiResourceController.Call_CreateApiResourceAsync(ApiResourceControllerExtensions.GetDefaultApiResource(1), Admin);
        var createdApiResource2 = await _apiResourceController.Call_CreateApiResourceAsync(ApiResourceControllerExtensions.GetDefaultApiResource(1), Admin);
        var ts = DateTime.UtcNow;
        await _apiResourceController.Call_UpdateApiResourceAsync(new ApiResourceDtoUpdate
        {
            Id = createdApiResource2.Id,
            Description = "UpdatedDescription",
        }, Admin);

        // Act
        var resources = await _apiResourceController.Call_GetApiResourcesPagedAsync(Admin);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(resources, Has.Count.EqualTo(2));
            Assert.That(resources.First(r => r.Id == createdApiResource1.Id).Updated, Is.Null);
            Assert.That(resources.First(r => r.Id == createdApiResource2.Id).Updated, Is.GreaterThanOrEqualTo(ts).And.LessThanOrEqualTo(DateTime.UtcNow));
        }
    }

    [Test]
    public async Task GetApiResourcesPagedAsync_WithLastModifiedData_ReturnsListWithTimestamps()
    {
        // Arrange
        var createdApiResource1 = await _apiResourceController.Call_CreateApiResourceAsync(ApiResourceControllerExtensions.GetDefaultApiResource(1), Admin);
        var createdApiResource2 = await _apiResourceController.Call_CreateApiResourceAsync(ApiResourceControllerExtensions.GetDefaultApiResource(1), Admin);

        var ts1 = DateTime.UtcNow.AddMinutes(-10);
        var ts2 = DateTime.UtcNow.AddMinutes(-5);

        var lastModifiedDict = new Dictionary<int, EntityLastModifiedData>
        {
            { createdApiResource1.Id, new EntityLastModifiedData { Id = createdApiResource1.Id, LastModified = ts1 } },
            { createdApiResource2.Id, new EntityLastModifiedData { Id = createdApiResource2.Id, LastModified = ts2 } }
        };

        _apiResourceAuditService.GetLastModifiedByIdAsync(Arg.Any<List<int>>()).Returns(lastModifiedDict);

        // Act
        var resources = await _apiResourceController.Call_GetApiResourcesPagedAsync(Admin);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(resources, Has.Count.EqualTo(2));
            Assert.That(resources.FirstOrDefault(r => r.Id == createdApiResource1.Id)?.Updated, Is.EqualTo(ts1));
            Assert.That(resources.FirstOrDefault(r => r.Id == createdApiResource2.Id)?.Updated, Is.EqualTo(ts2));
        }
    }
}
