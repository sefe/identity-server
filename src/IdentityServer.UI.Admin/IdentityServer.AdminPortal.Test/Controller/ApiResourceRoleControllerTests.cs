// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

using Microsoft.AspNetCore.Mvc;
using Microsoft.Extensions.DependencyInjection;
using IdentityServer.Abstraction.Exceptions;
using IdentityServer.AdminPortal.Server.Controllers;
using IdentityServer.AdminPortal.Test.Extensions;
using IdentityServer.Tests.Common;

namespace IdentityServer.AdminPortal.Test.Controller;

public class ApiResourceRoleControllerTests : ControllerTestBase
{
    private ApiResourceController _apiResourceController;
    private ApiResourcePropertyRoleController _apiResourceRoleController;

    [SetUp]
    public async Task Setup()
    {
        var provider = IoC.GetProvider(sc =>
        {
            sc.AddScoped<ApiResourceController>();
            sc.AddScoped<ApiResourcePropertyRoleController>();
            sc.ReplaceWithInstance(EverythingIsAllowed);
        });

        await Setup(provider);

        _apiResourceController = provider.GetRequiredService<ApiResourceController>();
        _apiResourceRoleController = provider.GetRequiredService<ApiResourcePropertyRoleController>();
    }

    [Test]
    public async Task CreateRole_WithInvalidApiResource_Fails()
    {
        // Arrange
        var newRole = ApiResourceRoleControllerExtensions.NewRoleFor(0, "TestRole");
        SetControllerContext(_apiResourceRoleController, Admin);

        // Act
        var response = await _apiResourceRoleController.CreatePropertyAsync(newRole);

        // Assert
        Assert.That(response.Result, Is.TypeOf<BadRequestObjectResult>());
    }

    [Test]
    public void CreateRole_WithMissingApiResource_Fails()
    {
        // Arrange
        var newRole = ApiResourceRoleControllerExtensions.NewRoleFor(999, "TestRole");

        // Act & Assert
        Assert.ThrowsAsync<EntityNotFoundException>(() => _apiResourceRoleController.Call_AddApiResourceRoleAsync(newRole, Admin));
    }

    [Test]
    public async Task CreateRole_IfValid_SucceedsAndIsVisibleInApiResource()
    {
        // Arrange
        var createdApiResource = await _apiResourceController.Call_CreateApiResourceAsync(ApiResourceControllerExtensions.GetDefaultApiResource(1), Admin);
        var newRole = ApiResourceRoleControllerExtensions.NewRoleFor(createdApiResource.Id, "TestRole");

        // Act
        var createdRole = await _apiResourceRoleController.Call_AddApiResourceRoleAsync(newRole, Admin);
        var retrievedApiResource = await _apiResourceController.Call_GetApiResourceAsync(createdApiResource.Id, Admin);

        using (Assert.EnterMultipleScope())
        {
            // Assert
            Assert.That(createdRole.Id, Is.Not.Zero);
            Assert.That(createdRole.RoleName, Is.EqualTo(newRole.RoleName));
            Assert.That(createdRole.ApiResourceId, Is.EqualTo(createdApiResource.Id));

            Assert.That(retrievedApiResource.Roles, Has.Count.EqualTo(1));
        }
        var retrievedRole = retrievedApiResource.Roles[0];
        using (Assert.EnterMultipleScope())
        {
            Assert.That(retrievedRole.Id, Is.Not.Zero);
            Assert.That(retrievedRole.ApiResourceId, Is.EqualTo(createdApiResource.Id));
            Assert.That(retrievedRole.RoleName, Is.EqualTo(newRole.RoleName));
        }
    }

    [Test]
    public async Task CreateRole_WithDuplicateName_Fails()
    {
        // Arrange
        var createdApiResource = await _apiResourceController.Call_CreateApiResourceAsync(ApiResourceControllerExtensions.GetDefaultApiResource(1), Admin);
        var newRole = ApiResourceRoleControllerExtensions.NewRoleFor(createdApiResource.Id, "TestRole");
        await _apiResourceRoleController.Call_AddApiResourceRoleAsync(newRole, Admin);

        // Act & Assert
        Assert.ThrowsAsync<EntityAlreadyExistsException>(() => _apiResourceRoleController.Call_AddApiResourceRoleAsync(newRole, Admin));
    }

    [Test]
    public async Task DeleteRole_IfValidId_Succeeds()
    {
        // Arrange
        var createdApiResource = await _apiResourceController.Call_CreateApiResourceAsync(ApiResourceControllerExtensions.GetDefaultApiResource(1), Admin);
        var newRole = ApiResourceRoleControllerExtensions.NewRoleFor(createdApiResource.Id, "TestRole");
        var createdRole = await _apiResourceRoleController.Call_AddApiResourceRoleAsync(newRole, Admin);

        // Act
        var deletedId = await _apiResourceRoleController.Call_DeleteApiResourceRoleAsync(createdRole.Id, Admin);

        // Assert
        Assert.That(deletedId, Is.EqualTo(createdRole.Id));
    }
}
