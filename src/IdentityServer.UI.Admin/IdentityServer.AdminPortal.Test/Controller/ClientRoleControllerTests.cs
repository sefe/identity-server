using Microsoft.AspNetCore.Mvc;
using Microsoft.Extensions.DependencyInjection;
using IdentityServer.Abstraction.Exceptions;
using IdentityServer.AdminPortal.Server.Controllers;
using IdentityServer.AdminPortal.Test.Extensions;
using IdentityServer.Tests.Common;

namespace IdentityServer.AdminPortal.Test.Controller;

public class ClientRoleControllerTests : ControllerTestBase
{
    private ClientController _clientController;
    private ClientPropertyRoleController _clientRoleController;

    [SetUp]
    public async Task Setup()
    {
        var provider = IoC.GetProvider(sc =>
        {
            sc.AddScoped<ClientController>();
            sc.AddScoped<ClientPropertyRoleController>();
            sc.ReplaceWithInstance(EverythingIsAllowed);
        });

        await Setup(provider);

        _clientController = provider.GetRequiredService<ClientController>();
        _clientRoleController = provider.GetRequiredService<ClientPropertyRoleController>();
    }

    [Test]
    public async Task CreateRole_WithInvalidClient_Fails()
    {
        // Arrange
        var newRole = ClientRoleControllerExtensions.NewRoleFor(0, "TestRole");
        SetControllerContext(_clientRoleController, Admin);

        // Act
        var response = await _clientRoleController.CreatePropertyAsync(newRole);

        // Assert
        Assert.That(response.Result, Is.TypeOf<BadRequestObjectResult>());
    }

    [Test]
    public void CreateRole_WithMissingClient_Fails()
    {
        // Arrange
        var newRole = ClientRoleControllerExtensions.NewRoleFor(999, "TestRole");

        // Act & Assert
        Assert.ThrowsAsync<EntityNotFoundException>(() => _clientRoleController.Call_AddClientRoleAsync(newRole, Admin));
    }

    [Test]
    public async Task CreateRole_IfValid_SucceedsAndIsVisibleInClient()
    {
        // Arrange
        var createdClient = await _clientController.Call_CreateClientAsync(ClientControllerExtensions.GetDefaultClient(1), Admin);
        var newRole = ClientRoleControllerExtensions.NewRoleFor(createdClient.Id, "TestRole");

        // Act
        var createdRole = await _clientRoleController.Call_AddClientRoleAsync(newRole, Admin);
        var retrievedClient = await _clientController.Call_GetClientAsync(createdClient.Id, Admin);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            // Assert
            Assert.That(createdRole.Id, Is.Not.Zero);
            Assert.That(createdRole.RoleName, Is.EqualTo(newRole.RoleName));
            Assert.That(createdRole.ClientId, Is.EqualTo(createdClient.Id));

            Assert.That(retrievedClient.Roles, Has.Count.EqualTo(1));
        }

        Assert.That(retrievedClient.Roles, Has.Count.EqualTo(1));
        var retrievedRole = retrievedClient.Roles[0];
        using (Assert.EnterMultipleScope())
        {
            Assert.That(retrievedRole.Id, Is.Not.Zero);
            Assert.That(retrievedRole.ClientId, Is.EqualTo(createdClient.Id));
            Assert.That(retrievedRole.RoleName, Is.EqualTo(newRole.RoleName));
        }
    }

    [Test]
    public async Task CreateRole_IfDuplicate_Fails()
    {
        // Arrange
        var createdClient = await _clientController.Call_CreateClientAsync(ClientControllerExtensions.GetDefaultClient(1), Admin);
        var newRole = ClientRoleControllerExtensions.NewRoleFor(createdClient.Id, "TestRole");
        await _clientRoleController.Call_AddClientRoleAsync(newRole, Admin);

        // Act
        Assert.ThrowsAsync<EntityAlreadyExistsException>(() => _clientRoleController.Call_AddClientRoleAsync(newRole, Admin));
    }

    [Test]
    public async Task DeleteRole_IfValidId_Succeeds()
    {
        // Arrange
        var createdClient = await _clientController.Call_CreateClientAsync(ClientControllerExtensions.GetDefaultClient(1), Admin);
        var newRole = ClientRoleControllerExtensions.NewRoleFor(createdClient.Id, "TestRole");
        var createdRole = await _clientRoleController.Call_AddClientRoleAsync(newRole, Admin);

        // Act
        var deletedId = await _clientRoleController.Call_DeleteClientRoleAsync(createdRole.Id, Admin);

        // Assert
        Assert.That(deletedId, Is.EqualTo(createdRole.Id));
    }
}
