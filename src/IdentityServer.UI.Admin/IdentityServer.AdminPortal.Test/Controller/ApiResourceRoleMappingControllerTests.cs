// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

using Microsoft.AspNetCore.Mvc;
using Microsoft.Extensions.DependencyInjection;
using NSubstitute;
using System.Linq.Expressions;
using IdentityServer.Abstraction.Contracts;
using IdentityServer.Abstraction.Contracts.MicrosoftGraph;
using IdentityServer.Abstraction.Entities.EntraEntities;
using IdentityServer.Abstraction.Entities.IdentityServerConfig;
using IdentityServer.Abstraction.Exceptions;
using IdentityServer.AdminPortal.Server.Controllers;
using IdentityServer.AdminPortal.Test.Extensions;
using IdentityServer.Data.DuendeEntityExtensions;
using IdentityServer.Tests.Common;
using IdentityServer.Tests.Common.Builders;

namespace IdentityServer.AdminPortal.Test.Controller;

public class ApiResourceRoleMappingControllerTests : ControllerTestBase
{
    private ApiResourceController _apiResourceController;
    private ApiResourcePropertyRoleController _apiResourceRoleController;
    private ApiResourcePropertyRoleMappingController _apiResourceRoleMappingController;
    private readonly IEntraGroupService _entraGroupService = Substitute.For<IEntraGroupService>();
    private readonly IEntraUserService _entraUserService = Substitute.For<IEntraUserService>();
    private readonly IStorage<ClientExt> _clientStorage = Substitute.For<IStorage<ClientExt>>();

    [SetUp]
    public async Task Setup()
    {
        var provider = IoC.GetProvider(sc =>
        {
            sc.AddScoped<ApiResourceController>();
            sc.AddScoped<ApiResourcePropertyRoleController>();
            sc.AddScoped<ApiResourcePropertyRoleMappingController>();
            sc.ReplaceWithInstance(EverythingIsAllowed);
            sc.ReplaceWithInstance(_clientStorage);

            sc.AddSingleton(_entraGroupService);
            sc.AddSingleton(_entraUserService);
        });

        await Setup(provider);

        _apiResourceController = provider.GetRequiredService<ApiResourceController>();
        _apiResourceRoleController = provider.GetRequiredService<ApiResourcePropertyRoleController>();
        _apiResourceRoleMappingController = provider.GetRequiredService<ApiResourcePropertyRoleMappingController>();
    }

    [Test]
    public async Task CreateRoleMapping_WithInvalidApiResource_Fails()
    {
        var newRoleMapping = ApiResourceRoleMappingControllerExtensions.NewRoleMappingFor(0, 1, RoleMapType.SecurityGroup, Guid.NewGuid().ToString());

        SetControllerContext(_apiResourceRoleMappingController, Admin);
        var response = await _apiResourceRoleMappingController.CreatePropertyAsync(newRoleMapping);
        Assert.That(response.Result, Is.TypeOf<BadRequestObjectResult>());
    }

    [Test]
    public void CreateRoleMapping_WithMissingApiResource_Fails()
    {
        var newRoleMapping = ApiResourceRoleMappingControllerExtensions.NewRoleMappingFor(999, 1, RoleMapType.SecurityGroup, Guid.NewGuid().ToString());

        Assert.ThrowsAsync<EntityNotFoundException>(() => _apiResourceRoleMappingController.Call_AddApiResourceRoleMappingAsync(newRoleMapping, Admin));
    }

    [Test]
    public async Task CreateRoleMapping_IfValid_SucceedsAndVisibleInApiResource()
    {
        // Arrange
        var (oid, name) = _entraGroupService.SetupSecurityGroupResponse();
        var createdApiResource = await _apiResourceController.Call_CreateApiResourceAsync(ApiResourceControllerExtensions.GetDefaultApiResource(1), Admin);
        var createdRole = await _apiResourceRoleController.Call_AddApiResourceRoleAsync(ApiResourceRoleControllerExtensions.NewRoleFor(createdApiResource.Id, "TestRole"), Admin);
        var newRoleMapping = ApiResourceRoleMappingControllerExtensions.NewRoleMappingFor(createdApiResource.Id, createdRole.Id, RoleMapType.SecurityGroup, oid);

        // Act
        var createdMapping = await _apiResourceRoleMappingController.Call_AddApiResourceRoleMappingAsync(newRoleMapping, Admin);
        var retrievedApiResource = await _apiResourceController.Call_GetApiResourceAsync(createdApiResource.Id, Admin);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(createdMapping.Id, Is.Not.Zero);
            Assert.That(createdMapping.ApiResourceRoleId, Is.EqualTo(createdRole.Id));
            Assert.That(createdMapping.MappingType, Is.EqualTo(newRoleMapping.MappingType));
            Assert.That(createdMapping.Value, Is.EqualTo(newRoleMapping.Value));
            Assert.That(createdMapping.Description, Is.EqualTo(name));
        }
        var retrievedRole = retrievedApiResource.Roles.Single(r => r.Id == createdRole.Id);
        Assert.That(retrievedRole.Mappings, Has.Count.EqualTo(1));
        var retrievedRoleMapping = retrievedRole.Mappings[0];
        using (Assert.EnterMultipleScope())
        {
            Assert.That(retrievedRoleMapping.Id, Is.Not.Zero);
            Assert.That(retrievedRoleMapping.ApiResourceRoleId, Is.EqualTo(createdRole.Id));
            Assert.That(retrievedRoleMapping.MappingType, Is.EqualTo(newRoleMapping.MappingType));
            Assert.That(retrievedRoleMapping.Value, Is.EqualTo(newRoleMapping.Value));
        }
    }

    [Test]
    public async Task CreateRoleMapping_WithDuplicate_Fails()
    {
        // Arrange
        var (oid, _) = _entraGroupService.SetupSecurityGroupResponse();
        var createdApiResource = await _apiResourceController.Call_CreateApiResourceAsync(ApiResourceControllerExtensions.GetDefaultApiResource(1), Admin);
        var createdRole = await _apiResourceRoleController.Call_AddApiResourceRoleAsync(ApiResourceRoleControllerExtensions.NewRoleFor(createdApiResource.Id, "TestRole"), Admin);
        var newRoleMapping = ApiResourceRoleMappingControllerExtensions.NewRoleMappingFor(createdApiResource.Id, createdRole.Id, RoleMapType.SecurityGroup, oid);
        await _apiResourceRoleMappingController.Call_AddApiResourceRoleMappingAsync(newRoleMapping, Admin);

        // Act
        Assert.ThrowsAsync<EntityAlreadyExistsException>(() => _apiResourceRoleMappingController.Call_AddApiResourceRoleMappingAsync(newRoleMapping, Admin));
    }

    [Test]
    public async Task CreateRoleMapping_WithInvalidSecurityGroup_Fails()
    {
        // Arrange
        var groupObjectId = Guid.NewGuid().ToString();
        _entraGroupService.GetGroupByObjectIdAsync(Arg.Any<string>()).Returns(new GroupResponse());

        var createdApiResource = await _apiResourceController.Call_CreateApiResourceAsync(ApiResourceControllerExtensions.GetDefaultApiResource(1), Admin);
        var createdRole = await _apiResourceRoleController.Call_AddApiResourceRoleAsync(ApiResourceRoleControllerExtensions.NewRoleFor(createdApiResource.Id, "TestRole"), Admin);
        var newRoleMapping = ApiResourceRoleMappingControllerExtensions.NewRoleMappingFor(createdApiResource.Id, createdRole.Id, RoleMapType.SecurityGroup, groupObjectId);

        // Act & Assert
        Assert.ThrowsAsync<EntityValidationException>(() => _apiResourceRoleMappingController.Call_AddApiResourceRoleMappingAsync(newRoleMapping, Admin));
    }

    [Test]
    public async Task CreateRoleMapping_WithValidSecurityGroup_Succeeds()
    {
        // Arrange
        var (oid, name) = _entraGroupService.SetupSecurityGroupResponse();
        var createdApiResource = await _apiResourceController.Call_CreateApiResourceAsync(ApiResourceControllerExtensions.GetDefaultApiResource(1), Admin);
        var createdRole = await _apiResourceRoleController.Call_AddApiResourceRoleAsync(ApiResourceRoleControllerExtensions.NewRoleFor(createdApiResource.Id, "TestRole"), Admin);
        var newRoleMapping = ApiResourceRoleMappingControllerExtensions.NewRoleMappingFor(createdApiResource.Id, createdRole.Id, RoleMapType.SecurityGroup, oid);

        // Act
        var mappingResponse = await _apiResourceRoleMappingController.Call_AddApiResourceRoleMappingAsync(newRoleMapping, Admin);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(mappingResponse.Id, Is.Not.Zero);
            Assert.That(mappingResponse.ApiResourceRoleId, Is.EqualTo(createdRole.Id));
            Assert.That(mappingResponse.MappingType, Is.EqualTo(newRoleMapping.MappingType));
            Assert.That(mappingResponse.Value, Is.EqualTo(newRoleMapping.Value));
            Assert.That(mappingResponse.Description, Is.EqualTo(name));
        }
    }

    [Test]
    public async Task CreateRoleMapping_WithInvalidUser_Fails()
    {
        // Arrange
        var userObjectId = Guid.NewGuid().ToString();
        _entraUserService.GetUserByObjectIdAsync(Arg.Any<string>()).Returns(new UserResponse());

        var createdApiResource = await _apiResourceController.Call_CreateApiResourceAsync(ApiResourceControllerExtensions.GetDefaultApiResource(1), Admin);
        var createdRole = await _apiResourceRoleController.Call_AddApiResourceRoleAsync(ApiResourceRoleControllerExtensions.NewRoleFor(createdApiResource.Id, "TestRole"), Admin);
        var newRoleMapping = ApiResourceRoleMappingControllerExtensions.NewRoleMappingFor(createdApiResource.Id, createdRole.Id, RoleMapType.UserObjectId, userObjectId);

        // Act & Assert
        Assert.ThrowsAsync<EntityValidationException>(() => _apiResourceRoleMappingController.Call_AddApiResourceRoleMappingAsync(newRoleMapping, Admin));
    }

    [Test]
    public async Task CreateRoleMapping_WithValidUser_Succeeds()
    {
        // Arrange
        var (oid, name) = _entraUserService.SetupUserResponse();
        var createdApiResource = await _apiResourceController.Call_CreateApiResourceAsync(ApiResourceControllerExtensions.GetDefaultApiResource(1), Admin);
        var createdRole = await _apiResourceRoleController.Call_AddApiResourceRoleAsync(ApiResourceRoleControllerExtensions.NewRoleFor(createdApiResource.Id, "TestRole"), Admin);
        var newRoleMapping = ApiResourceRoleMappingControllerExtensions.NewRoleMappingFor(createdApiResource.Id, createdRole.Id, RoleMapType.UserObjectId, oid);

        // Act
        var mappingResponse = await _apiResourceRoleMappingController.Call_AddApiResourceRoleMappingAsync(newRoleMapping, Admin);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(mappingResponse.Id, Is.Not.Zero);
            Assert.That(mappingResponse.ApiResourceRoleId, Is.EqualTo(createdRole.Id));
            Assert.That(mappingResponse.MappingType, Is.EqualTo(newRoleMapping.MappingType));
            Assert.That(mappingResponse.Value, Is.EqualTo(newRoleMapping.Value));
            Assert.That(mappingResponse.Description, Is.EqualTo(name));
        }
    }

    [Test]
    public async Task CreateRoleMapping_WithInvalidClient_Fails()
    {
        // Arrange
        var clientId = Guid.NewGuid().ToString();
        // do not add client to storage
        _clientStorage.GetByIdAsync(Arg.Any<int>()).Returns((ClientExt)null);
        _clientStorage.ToListAsync(Arg.Any<Expression<Func<ClientExt, bool>>>()).Returns(new List<ClientExt>());

        var createdApiResource = await _apiResourceController.Call_CreateApiResourceAsync(ApiResourceControllerExtensions.GetDefaultApiResource(1), Admin);
        var createdRole = await _apiResourceRoleController.Call_AddApiResourceRoleAsync(ApiResourceRoleControllerExtensions.NewRoleFor(createdApiResource.Id, "TestRole"), Admin);
        var newRoleMapping = ApiResourceRoleMappingControllerExtensions.NewRoleMappingFor(createdApiResource.Id, createdRole.Id, RoleMapType.ClientId, clientId);

        // Act & Assert
        Assert.ThrowsAsync<EntityValidationException>(() => _apiResourceRoleMappingController.Call_AddApiResourceRoleMappingAsync(newRoleMapping, Admin));
    }

    [Test]
    public async Task CreateRoleMapping_WithValidClient_Succeeds()
    {
        // Arrange
        var clientId = Guid.NewGuid().ToString();
        var clientMock = new ClientExtBuilder(clientId, clientId).Build();
        _clientStorage.GetByIdAsync(Arg.Any<int>()).Returns(clientMock);
        _clientStorage.ToListAsync(Arg.Any<Expression<Func<ClientExt, bool>>>()).Returns(new List<ClientExt> { clientMock });
        var createdApiResource = await _apiResourceController.Call_CreateApiResourceAsync(ApiResourceControllerExtensions.GetDefaultApiResource(1), Admin);
        var createdRole = await _apiResourceRoleController.Call_AddApiResourceRoleAsync(ApiResourceRoleControllerExtensions.NewRoleFor(createdApiResource.Id, "TestRole"), Admin);
        var newRoleMapping = ApiResourceRoleMappingControllerExtensions.NewRoleMappingFor(createdApiResource.Id, createdRole.Id, RoleMapType.ClientId, clientMock.ClientId);

        // Act
        var mappingResponse = await _apiResourceRoleMappingController.Call_AddApiResourceRoleMappingAsync(newRoleMapping, Admin);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(mappingResponse.Id, Is.Not.Zero);
            Assert.That(mappingResponse.ApiResourceRoleId, Is.EqualTo(createdRole.Id));
            Assert.That(mappingResponse.MappingType, Is.EqualTo(newRoleMapping.MappingType));
            Assert.That(mappingResponse.Value, Is.EqualTo(newRoleMapping.Value));
            Assert.That(mappingResponse.Description, Is.EqualTo(clientMock.ClientName));
        }
    }

    [Test]
    public async Task CreateRoleMapping_IfDuplicateClientMapping_Fails()
    {
        // Arrange
        var clientId = Guid.NewGuid().ToString();
        var clientMock = new ClientExtBuilder(clientId, clientId).Build();
        _clientStorage.GetByIdAsync(Arg.Any<int>()).Returns(clientMock);
        _clientStorage.ToListAsync(Arg.Any<Expression<Func<ClientExt, bool>>>()).Returns(new List<ClientExt> { clientMock });
        var createdApiResource = await _apiResourceController.Call_CreateApiResourceAsync(ApiResourceControllerExtensions.GetDefaultApiResource(1), Admin);
        var createdRole = await _apiResourceRoleController.Call_AddApiResourceRoleAsync(ApiResourceRoleControllerExtensions.NewRoleFor(createdApiResource.Id, "TestRole"), Admin);
        var newRoleMapping = ApiResourceRoleMappingControllerExtensions.NewRoleMappingFor(createdApiResource.Id, createdRole.Id, RoleMapType.ClientId, clientMock.ClientId);
        _ = await _apiResourceRoleMappingController.Call_AddApiResourceRoleMappingAsync(newRoleMapping, Admin);

        // Act & Assert
        Assert.ThrowsAsync<EntityAlreadyExistsException>(() => _apiResourceRoleMappingController.Call_AddApiResourceRoleMappingAsync(newRoleMapping, Admin));
    }

    [Test]
    public async Task CreateRoleMapping_IfDuplicateUserMapping_Fails()
    {
        // Arrange
        var (oid, _) = _entraUserService.SetupUserResponse();
        var createdApiResource = await _apiResourceController.Call_CreateApiResourceAsync(ApiResourceControllerExtensions.GetDefaultApiResource(1), Admin);
        var createdRole = await _apiResourceRoleController.Call_AddApiResourceRoleAsync(ApiResourceRoleControllerExtensions.NewRoleFor(createdApiResource.Id, "TestRole"), Admin);
        var newRoleMapping = ApiResourceRoleMappingControllerExtensions.NewRoleMappingFor(createdApiResource.Id, createdRole.Id, RoleMapType.UserObjectId, oid);
        _ = await _apiResourceRoleMappingController.Call_AddApiResourceRoleMappingAsync(newRoleMapping, Admin);

        // Act & Assert
        Assert.ThrowsAsync<EntityAlreadyExistsException>(() => _apiResourceRoleMappingController.Call_AddApiResourceRoleMappingAsync(newRoleMapping, Admin));
    }

    [Test]
    public async Task CreateRoleMapping_IfDuplicateSecurityGroupMapping_Fails()
    {
        // Arrange
        var (oid, _) = _entraGroupService.SetupSecurityGroupResponse();
        var createdApiResource = await _apiResourceController.Call_CreateApiResourceAsync(ApiResourceControllerExtensions.GetDefaultApiResource(1), Admin);
        var createdRole = await _apiResourceRoleController.Call_AddApiResourceRoleAsync(ApiResourceRoleControllerExtensions.NewRoleFor(createdApiResource.Id, "TestRole"), Admin);
        var newRoleMapping = ApiResourceRoleMappingControllerExtensions.NewRoleMappingFor(createdApiResource.Id, createdRole.Id, RoleMapType.SecurityGroup, oid);
        _ = await _apiResourceRoleMappingController.Call_AddApiResourceRoleMappingAsync(newRoleMapping, Admin);

        // Act & Assert
        Assert.ThrowsAsync<EntityAlreadyExistsException>(() => _apiResourceRoleMappingController.Call_AddApiResourceRoleMappingAsync(newRoleMapping, Admin));
    }
    [Test]
    public async Task Delete_WhenMappingExists_Succeeds()
    {
        // Arrange
        var userObjectId = Guid.NewGuid().ToString();
        const string userDisplayName = "Test Group";
        _entraUserService.GetUserByObjectIdAsync(Arg.Any<string>()).Returns(new UserResponse { Users = new() { new User { OId = userObjectId, DisplayName = userDisplayName, AccountEnabled = true } } });

        var createdApiResource = await _apiResourceController.Call_CreateApiResourceAsync(ApiResourceControllerExtensions.GetDefaultApiResource(1), Admin);
        var createdRole = await _apiResourceRoleController.Call_AddApiResourceRoleAsync(ApiResourceRoleControllerExtensions.NewRoleFor(createdApiResource.Id, "TestRole"), Admin);
        var newRoleMapping = ApiResourceRoleMappingControllerExtensions.NewRoleMappingFor(createdApiResource.Id, createdRole.Id, RoleMapType.UserObjectId, userObjectId);
        var createdMapping = await _apiResourceRoleMappingController.Call_AddApiResourceRoleMappingAsync(newRoleMapping, Admin);

        // Act
        var deletedId = await _apiResourceRoleMappingController.Call_DeleteApiResourceRoleMappingAsync(createdMapping.Id, Admin);

        // Assert
        Assert.That(deletedId, Is.EqualTo(createdMapping.Id));
    }
}
