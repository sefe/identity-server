// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

using Microsoft.AspNetCore.Mvc;
using Microsoft.Extensions.DependencyInjection;
using NSubstitute;
using IdentityServer.Abstraction.Contracts;
using IdentityServer.Abstraction.DTO.Clients;
using IdentityServer.Abstraction.Entities.IdentityServerConfig;
using IdentityServer.Abstraction.Entities.IdentityServerConfig.SystemPermissions;
using IdentityServer.Abstraction.Exceptions;
using IdentityServer.AdminPortal.Server.Controllers;
using IdentityServer.AdminPortal.Test.Extensions;
using IdentityServer.Tests.Common;
using DataEntities = Duende.IdentityServer.EntityFramework.Entities;

namespace IdentityServer.AdminPortal.Test.Controller;

public class ClientGrantControllerTests : ControllerTestBase
{
    private ClientPropertyGrantController _clientGrantController;
    private ClientController _clientController;
    private ICache<DataEntities.Client> _clientCache;

    [SetUp]
    public async Task Setup()
    {
        _clientCache = Substitute.For<ICache<DataEntities.Client>>();

        var provider = IoC.GetProvider(sc =>
        {
            sc.AddScoped<ClientPropertyGrantController>();
            sc.AddScoped<ClientController>();
            sc.ReplaceWithInstance(EverythingIsAllowed);
            sc.ReplaceWithInstance(_clientCache);
        });

        await Setup(provider);

        _clientGrantController = provider.GetRequiredService<ClientPropertyGrantController>();
        _clientController = provider.GetRequiredService<ClientController>();
    }

    [Test]
    public async Task AddClientGrantAsync_WithValidGrantType_Succeeds()
    {
        // Arrange
        var grantType = ClientGrantTypeNames.Grant_Code;
        var client = await _clientController.Call_CreateClientAsync(ClientControllerExtensions.GetDefaultClient(1), Contributor);

        // Act
        var addedGrant = await _clientGrantController.Call_AddClientGrantAsync(client.Id, grantType, Contributor);
        var updatedClient = await _clientController.Call_GetClientAsync(client.Id, Contributor);

        // Assert
        ClientGrantControllerExtensions.AssertClientGrantIsValid(addedGrant, client.Id, grantType);
        ClientGrantControllerExtensions.AssertClientHasGrantType(updatedClient, grantType);
    }

    [Test]
    public async Task AddClientGrantAsync_WithDuplicateGrantType_Fails()
    {
        // Arrange
        var grantType = ClientGrantTypeNames.Grant_Code;
        var client = await _clientController.Call_CreateClientAsync(ClientControllerExtensions.GetDefaultClient(1), Contributor);
        await _clientGrantController.Call_AddClientGrantAsync(client.Id, grantType, Contributor);

        // Act
        Assert.ThrowsAsync<EntityAlreadyExistsException>(() => _clientGrantController.Call_AddClientGrantAsync(client.Id, grantType, Contributor));
    }

    [Test]
    public async Task AddClientGrantAsync_WithInvalidGrantType_Fails()
    {
        // Arrange
        var invalidGrantType = "invalid-grant";
        var client = await _clientController.Call_CreateClientAsync(ClientControllerExtensions.GetDefaultClient(1), Contributor);
        SetControllerContext(_clientGrantController, Contributor);
        var grantDto = new ClientPropertyGrantDtoCreate
        {
            ClientId = client.Id,
            GrantType = invalidGrantType
        };

        // Act
        var response = await _clientGrantController.CreatePropertyAsync(grantDto);

        // Assert
        Assert.That(response.Result, Is.TypeOf<BadRequestObjectResult>());
    }

    [Test]
    public async Task AddClientGrantAsync_InvalidatesCache()
    {
        // Arrange
        var grantType = ClientGrantTypeNames.Grant_Code;
        var client = await _clientController.Call_CreateClientAsync(ClientControllerExtensions.GetDefaultClient(1), Contributor);

        // Act
        await _clientGrantController.Call_AddClientGrantAsync(client.Id, grantType, Contributor);

        // Assert
        await _clientCache.Received(1).RemoveAsync(client.ClientId);
    }

    [Test]
    public async Task AddClientGrantAsync_IfImplicitGrant_WithClientAllowRefreshToken_ThrowsException()
    {
        // Arrange
        var grantType = ClientGrantTypeNames.Grant_Implicit;
        var client = await _clientController.Call_CreateClientAsync(ClientControllerExtensions.GetDefaultClient(1), Admin);
        client = await _clientController.Call_UpdateClientAsync(new ClientDtoUpdate { Id = client.Id, AllowOfflineAccess = true }, Admin);

        // Act & Assert
        Assert.ThrowsAsync<EntityReferenceException>(() => _clientGrantController.Call_AddClientGrantAsync(client.Id, grantType, Admin));
    }

    [Test]
    public async Task DeleteClientGrantAsync_IfLastClientGrantType_FailsWithException()
    {
        // Arrange
        // by default a client is created with a single grant type
        var client = await _clientController.Call_CreateClientAsync(ClientControllerExtensions.GetDefaultClient(1), Contributor);

        // Act & Assert
        var ex = Assert.ThrowsAsync<EntityReferenceException>(async () => await _clientGrantController.Call_DeleteClientGrantAsync(client.AllowedGrantTypes[0].Id, Contributor));
        Assert.That(ex.Message, Is.EqualTo("Cannot remove the last Grant Type."));

        var persistedClient = await _clientController.Call_GetClientAsync(client.Id, Contributor);
        Assert.That(persistedClient.AllowedGrantTypes, Has.Count.EqualTo(1));
    }

    [Test]
    public async Task DeleteClientGrantAsync_IfExists_Succeeds()
    {
        // Arrange
        var grantType = ClientGrantTypeNames.Grant_Code;
        var client = await _clientController.Call_CreateClientAsync(ClientControllerExtensions.GetDefaultClient(1), Contributor);
        var addedGrant = await _clientGrantController.Call_AddClientGrantAsync(client.Id, grantType, Contributor);

        // Act
        var deletedId = await _clientGrantController.Call_DeleteClientGrantAsync(addedGrant.Id, Contributor);
        var updatedClient = await _clientController.Call_GetClientAsync(client.Id, Contributor);

        // Assert
        Assert.That(deletedId, Is.EqualTo(addedGrant.Id));
        ClientGrantControllerExtensions.AssertClientDoesNotHaveGrantType(updatedClient, grantType);
    }

    [Test]
    public async Task DeleteClientGrantAsync_IfMissingClientGrantType_ReturnsNotFound()
    {
        // Arrange
        var nonExistentId = 999;

        // Act & Assert
        SetControllerContext(_clientGrantController, Contributor);
        var response = await _clientGrantController.DeletePropertyByIdAsync(nonExistentId);
        Assert.That(response.Result, Is.TypeOf<NotFoundResult>());
    }

    [Test]
    public async Task DeleteClientGrantAsync_InvalidatesCache()
    {
        // Arrange
        var grantType = ClientGrantTypeNames.Grant_Code;
        var client = await _clientController.Call_CreateClientAsync(ClientControllerExtensions.GetDefaultClient(1), Contributor);
        var addedGrant = await _clientGrantController.Call_AddClientGrantAsync(client.Id, grantType, Contributor);

        // Reset the mock to clear previous calls
        _clientCache.ClearReceivedCalls();

        // Act
        await _clientGrantController.Call_DeleteClientGrantAsync(addedGrant.Id, Contributor);

        // Assert
        await _clientCache.Received(1).RemoveAsync(client.ClientId);
    }

    [Test]
    public async Task UpdateClient_EnableRefreshToken_IfClientAllowsImplicitGrant_ThrowsException()
    {
        // Arrange
        var grantType = ClientGrantTypeNames.Grant_Implicit;
        var client = await _clientController.Call_CreateClientAsync(ClientControllerExtensions.GetDefaultClient(1), Admin);
        await _clientGrantController.Call_AddClientGrantAsync(client.Id, grantType, Admin);

        // Act & Assert
        Assert.ThrowsAsync<InvalidOperationException>(() =>
            _clientController.Call_UpdateClientAsync(new ClientDtoUpdate { Id = client.Id, AllowOfflineAccess = true }, Admin));
    }

    [TestCaseSource(nameof(GetIncompatibleGrantTypes))]
    public async Task Add_IncompatibleGrant_ThrowsException(string existingGrant, string newGrant)
    {
        // Arrange
        var client = await _clientController.Call_CreateClientAsync(ClientControllerExtensions.GetDefaultClient(1), Admin);
        await _clientGrantController.Call_AddClientGrantAsync(client.Id, existingGrant, Contributor);

        // Act & Assert
        Assert.ThrowsAsync<EntityReferenceException>(() => _clientGrantController.Call_AddClientGrantAsync(client.Id, newGrant, Admin));
    }

    private static IEnumerable<TestCaseData> GetIncompatibleGrantTypes()
    {
        foreach (var (g1, g2) in ClientGrantTypeNames.IncompatibleGrantPairs)
        {
            yield return new TestCaseData(g1, g2);
            yield return new TestCaseData(g2, g1);
        }
    }
}
