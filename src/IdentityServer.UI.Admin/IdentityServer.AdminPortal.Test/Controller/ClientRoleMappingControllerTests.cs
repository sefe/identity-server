// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

using Microsoft.AspNetCore.Mvc;
using Microsoft.Extensions.DependencyInjection;
using NSubstitute;
using IdentityServer.Abstraction.Contracts.MicrosoftGraph;
using IdentityServer.Abstraction.Entities.EntraEntities;
using IdentityServer.Abstraction.Entities.IdentityServerConfig;
using IdentityServer.Abstraction.Exceptions;
using IdentityServer.AdminPortal.Server.Controllers;
using IdentityServer.AdminPortal.Test.Extensions;
using IdentityServer.Tests.Common;

namespace IdentityServer.AdminPortal.Test.Controller;

public class ClientRoleMappingControllerTests : ControllerTestBase
{
    private ClientController _clientController;
    private ClientPropertyRoleController _clientRoleController;
    private ClientPropertyRoleMappingController _clientRoleMappingController;
    private readonly IEntraGroupService _entraGroupService = Substitute.For<IEntraGroupService>();
    private readonly IEntraUserService _entraUserService = Substitute.For<IEntraUserService>();

    [SetUp]
    public async Task Setup()
    {
        var provider = IoC.GetProvider(sc =>
        {
            sc.AddScoped<ClientController>();
            sc.AddScoped<ClientPropertyRoleController>();
            sc.AddScoped<ClientPropertyRoleMappingController>();
            sc.ReplaceWithInstance(EverythingIsAllowed);

            sc.AddSingleton(_entraGroupService);
            sc.AddSingleton(_entraUserService);
        });

        await Setup(provider);

        _clientController = provider.GetRequiredService<ClientController>();
        _clientRoleController = provider.GetRequiredService<ClientPropertyRoleController>();
        _clientRoleMappingController = provider.GetRequiredService<ClientPropertyRoleMappingController>();
    }

    [Test]
    public async Task CreateRoleMapping_WithInvalidClient_Fails()
    {
        // Arrange
        var newRoleMapping = ClientRoleMappingControllerExtensions.NewRoleMappingFor(0, 1, ClientRoleMapType.SecurityGroup, Guid.NewGuid().ToString());
        SetControllerContext(_clientRoleMappingController, Admin);

        // Act
        var response = await _clientRoleMappingController.CreatePropertyAsync(newRoleMapping);

        // Assert
        Assert.That(response.Result, Is.TypeOf<BadRequestObjectResult>());
    }

    [Test]
    public void CreateRoleMapping_WithMissingClient_Fails()
    {
        // Arrange
        var newRoleMapping = ClientRoleMappingControllerExtensions.NewRoleMappingFor(999, 1, ClientRoleMapType.SecurityGroup, Guid.NewGuid().ToString());

        // Act & Assert
        Assert.ThrowsAsync<EntityNotFoundException>(() => _clientRoleMappingController.Call_AddClientRoleMappingAsync(newRoleMapping, Admin));
    }

    [Test]
    public async Task CreateRoleMapping_IfValid_SucceedsAndVisibleInClient()
    {
        // Arrange
        var (oid, name) = _entraGroupService.SetupSecurityGroupResponse();
        var createdClient = await _clientController.Call_CreateClientAsync(ClientControllerExtensions.GetDefaultClient(1), Admin);
        var createdRole = await _clientRoleController.Call_AddClientRoleAsync(ClientRoleControllerExtensions.NewRoleFor(createdClient.Id, "TestRole"), Admin);
        var newRoleMapping = ClientRoleMappingControllerExtensions.NewRoleMappingFor(createdClient.Id, createdRole.Id, ClientRoleMapType.SecurityGroup, oid);

        // Act
        var createdMapping = await _clientRoleMappingController.Call_AddClientRoleMappingAsync(newRoleMapping, Admin);
        var retrievedClient = await _clientController.Call_GetClientAsync(createdClient.Id, Admin);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(createdMapping.Id, Is.Not.Zero);
            Assert.That(createdMapping.ClientRoleId, Is.EqualTo(createdRole.Id));
            Assert.That(createdMapping.MappingType, Is.EqualTo(newRoleMapping.MappingType));
            Assert.That(createdMapping.Value, Is.EqualTo(newRoleMapping.Value));
            Assert.That(createdMapping.Description, Is.EqualTo(name));
        }
        var retrievedRole = retrievedClient.Roles.Single(r => r.Id == createdRole.Id);
        Assert.That(retrievedRole.Mappings, Has.Count.EqualTo(1));
        var retrievedRoleMapping = retrievedRole.Mappings[0];
        using (Assert.EnterMultipleScope())
        {
            Assert.That(retrievedRoleMapping.Id, Is.Not.Zero);
            Assert.That(retrievedRoleMapping.ClientRoleId, Is.EqualTo(createdRole.Id));
            Assert.That(retrievedRoleMapping.MappingType, Is.EqualTo(newRoleMapping.MappingType));
            Assert.That(retrievedRoleMapping.Value, Is.EqualTo(newRoleMapping.Value));
        }
    }

    [Test]
    public async Task CreateRoleMapping_WithDuplicateSecurityGroup_Fails()
    {
        // Arrange
        var (oid, _) = _entraGroupService.SetupSecurityGroupResponse();
        var createdClient = await _clientController.Call_CreateClientAsync(ClientControllerExtensions.GetDefaultClient(1), Admin);
        var createdRole = await _clientRoleController.Call_AddClientRoleAsync(ClientRoleControllerExtensions.NewRoleFor(createdClient.Id, "TestRole"), Admin);
        var newRoleMapping = ClientRoleMappingControllerExtensions.NewRoleMappingFor(createdClient.Id, createdRole.Id, ClientRoleMapType.SecurityGroup, oid);
        await _clientRoleMappingController.Call_AddClientRoleMappingAsync(newRoleMapping, Admin);

        // Act & Assert
        Assert.ThrowsAsync<EntityAlreadyExistsException>(() => _clientRoleMappingController.Call_AddClientRoleMappingAsync(newRoleMapping, Admin));
    }

    [Test]
    public async Task CreateRoleMapping_WithInvalidSecurityGroup_Fails()
    {
        // Arrange
        var groupObjectId = Guid.NewGuid().ToString();
        _entraGroupService.GetGroupByObjectIdAsync(Arg.Any<string>()).Returns(new GroupResponse());

        var createdClient = await _clientController.Call_CreateClientAsync(ClientControllerExtensions.GetDefaultClient(1), Admin);
        var createdRole = await _clientRoleController.Call_AddClientRoleAsync(ClientRoleControllerExtensions.NewRoleFor(createdClient.Id, "TestRole"), Admin);
        var newRoleMapping = ClientRoleMappingControllerExtensions.NewRoleMappingFor(createdClient.Id, createdRole.Id, ClientRoleMapType.SecurityGroup, groupObjectId);

        Assert.ThrowsAsync<EntityValidationException>(() => _clientRoleMappingController.Call_AddClientRoleMappingAsync(newRoleMapping, Admin));
    }

    [Test]
    public async Task CreateRoleMapping_WithValidSecurityGroup_Succeeds()
    {
        // Arrange
        var (oid, name) = _entraGroupService.SetupSecurityGroupResponse();
        var createdClient = await _clientController.Call_CreateClientAsync(ClientControllerExtensions.GetDefaultClient(1), Admin);
        var createdRole = await _clientRoleController.Call_AddClientRoleAsync(ClientRoleControllerExtensions.NewRoleFor(createdClient.Id, "TestRole"), Admin);
        var newRoleMapping = ClientRoleMappingControllerExtensions.NewRoleMappingFor(createdClient.Id, createdRole.Id, ClientRoleMapType.SecurityGroup, oid);

        // Act
        var mappingResponse = await _clientRoleMappingController.Call_AddClientRoleMappingAsync(newRoleMapping, Admin);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(mappingResponse.Id, Is.Not.Zero);
            Assert.That(mappingResponse.ClientRoleId, Is.EqualTo(createdRole.Id));
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

        var createdClient = await _clientController.Call_CreateClientAsync(ClientControllerExtensions.GetDefaultClient(1), Admin);
        var createdRole = await _clientRoleController.Call_AddClientRoleAsync(ClientRoleControllerExtensions.NewRoleFor(createdClient.Id, "TestRole"), Admin);
        var newRoleMapping = ClientRoleMappingControllerExtensions.NewRoleMappingFor(createdClient.Id, createdRole.Id, ClientRoleMapType.UserObjectId, userObjectId);

        Assert.ThrowsAsync<EntityValidationException>(() => _clientRoleMappingController.Call_AddClientRoleMappingAsync(newRoleMapping, Admin));
    }

    [Test]
    public async Task CreateRoleMapping_WithValidUser_Succeeds()
    {
        // Arrange
        var (oid, name) = _entraUserService.SetupUserResponse();
        var createdClient = await _clientController.Call_CreateClientAsync(ClientControllerExtensions.GetDefaultClient(1), Admin);
        var createdRole = await _clientRoleController.Call_AddClientRoleAsync(ClientRoleControllerExtensions.NewRoleFor(createdClient.Id, "TestRole"), Admin);
        var newRoleMapping = ClientRoleMappingControllerExtensions.NewRoleMappingFor(createdClient.Id, createdRole.Id, ClientRoleMapType.UserObjectId, oid);

        // Act
        var mappingResponse = await _clientRoleMappingController.Call_AddClientRoleMappingAsync(newRoleMapping, Admin);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(mappingResponse.Id, Is.Not.Zero);
            Assert.That(mappingResponse.ClientRoleId, Is.EqualTo(createdRole.Id));
            Assert.That(mappingResponse.MappingType, Is.EqualTo(newRoleMapping.MappingType));
            Assert.That(mappingResponse.Value, Is.EqualTo(newRoleMapping.Value));
            Assert.That(mappingResponse.Description, Is.EqualTo(name));
        }
    }

    [Test]
    public async Task CreateRoleMapping_WithDuplicateUser_Fails()
    {
        // Arrange
        var (oid, _) = _entraUserService.SetupUserResponse();
        var createdClient = await _clientController.Call_CreateClientAsync(ClientControllerExtensions.GetDefaultClient(1), Admin);
        var createdRole = await _clientRoleController.Call_AddClientRoleAsync(ClientRoleControllerExtensions.NewRoleFor(createdClient.Id, "TestRole"), Admin);
        var newRoleMapping = ClientRoleMappingControllerExtensions.NewRoleMappingFor(createdClient.Id, createdRole.Id, ClientRoleMapType.UserObjectId, oid);
        await _clientRoleMappingController.Call_AddClientRoleMappingAsync(newRoleMapping, Admin);

        // Act & Assert
        Assert.ThrowsAsync<EntityAlreadyExistsException>(() => _clientRoleMappingController.Call_AddClientRoleMappingAsync(newRoleMapping, Admin));
    }

    [Test]
    public async Task Delete_WhenMappingExists_Succeeds()
    {
        // Arrange
        var (oid, _) = _entraUserService.SetupUserResponse();
        var createdClient = await _clientController.Call_CreateClientAsync(ClientControllerExtensions.GetDefaultClient(1), Admin);
        var createdRole = await _clientRoleController.Call_AddClientRoleAsync(ClientRoleControllerExtensions.NewRoleFor(createdClient.Id, "TestRole"), Admin);
        var newRoleMapping = ClientRoleMappingControllerExtensions.NewRoleMappingFor(createdClient.Id, createdRole.Id, ClientRoleMapType.UserObjectId, oid);
        var createdMapping = await _clientRoleMappingController.Call_AddClientRoleMappingAsync(newRoleMapping, Admin);

        // Act
        var deletedId = await _clientRoleMappingController.Call_DeleteClientRoleMappingAsync(createdMapping.Id, Admin);

        // Assert
        Assert.That(deletedId, Is.EqualTo(createdMapping.Id));
    }
}
