// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

using Microsoft.AspNetCore.Mvc;
using Microsoft.Extensions.DependencyInjection;
using NSubstitute;
using IdentityServer.Abstraction.Contracts;
using IdentityServer.Abstraction.DTO.Clients;
using IdentityServer.Abstraction.Exceptions;
using IdentityServer.AdminPortal.Server.Controllers;
using IdentityServer.AdminPortal.Test.Extensions;
using IdentityServer.Tests.Common;
using DataEntities = Duende.IdentityServer.EntityFramework.Entities;
using CorsCacheEntry = Duende.IdentityServer.Stores.CachingCorsPolicyService<Duende.IdentityServer.EntityFramework.Services.CorsPolicyService>.CorsCacheEntry;

namespace IdentityServer.AdminPortal.Test.Controller;

[TestFixture]
public class ClientCorsControllerTests : ControllerTestBase
{
    private ClientPropertyCorsController _clientCorsController;
    private ClientController _clientController;
    private IConfigurationCacheInvalidator<DataEntities.Client> _clientCache;
    private IConfigurationCacheInvalidator<CorsCacheEntry> _corsCache;

    [SetUp]
    public async Task Setup()
    {
        _clientCache = Substitute.For<IConfigurationCacheInvalidator<DataEntities.Client>>();
        _corsCache = Substitute.For<IConfigurationCacheInvalidator<CorsCacheEntry>>();

        var provider = IoC.GetProvider(sc =>
        {
            sc.AddScoped<ClientPropertyCorsController>();
            sc.AddScoped<ClientController>();
            sc.ReplaceWithInstance(EverythingIsAllowed);
            sc.ReplaceWithInstance(_clientCache);
            sc.ReplaceWithInstance(_corsCache);
        });

        await Setup(provider);

        _clientCorsController = provider.GetRequiredService<ClientPropertyCorsController>();
        _clientController = provider.GetRequiredService<ClientController>();
    }

    [Test]
    public async Task AddClientCorsAsync_WithValidCorsOrigin_ReturnsCorsOriginAdded()
    {
        // Arrange
        var corsOrigin = "https://example.com";
        var client = await _clientController.Call_CreateClientAsync(ClientControllerExtensions.GetDefaultClient(1), Contributor);

        // Act
        var addedCors = await _clientCorsController.Call_AddClientCorsAsync(client.Id, corsOrigin, Contributor);
        var updatedClient = await _clientController.Call_GetClientAsync(client.Id, Contributor);

        // Assert
        ClientCorsControllerExtensions.AssertClientCorsIsValid(addedCors, client.Id, corsOrigin);
        ClientCorsControllerExtensions.AssertClientHasCorsOrigin(updatedClient, corsOrigin);
        await _corsCache.Received(1).RemoveAsync(corsOrigin);
    }

    [Test]
    public async Task AddClientCorsAsync_WithDuplicateCorsOrigin_Fails()
    {
        // Arrange
        var corsOrigin = "https://example.com";
        var client = await _clientController.Call_CreateClientAsync(ClientControllerExtensions.GetDefaultClient(1), Contributor);
        await _clientCorsController.Call_AddClientCorsAsync(client.Id, corsOrigin, Contributor);

        // Act & Assert
        await Assert.ThrowsAsync<EntityAlreadyExistsException>(() => _clientCorsController.Call_AddClientCorsAsync(client.Id, corsOrigin, Contributor));
    }

    [Test]
    public async Task AddClientCorsAsync_WithInvalidCorsOrigin_ReturnsBadRequest()
    {
        // Arrange
        var invalidCorsOrigin = "invalid-url";
        var client = await _clientController.Call_CreateClientAsync(ClientControllerExtensions.GetDefaultClient(1), Contributor);
        SetControllerContext(_clientCorsController, Contributor);

        // Act & Assert
        var corsDto = new ClientPropertyCorsOriginDtoCreate
        {
            ClientId = client.Id,
            Origin = invalidCorsOrigin
        };
        var response = await _clientCorsController.CreatePropertyAsync(corsDto);
        Assert.That(response.Result, Is.TypeOf<BadRequestObjectResult>());
    }

    [Test]
    public async Task DeleteClientCorsAsync_WithExistingCorsOrigin_ReturnsDeletedId()
    {
        // Arrange
        var corsOrigin = "https://example.com";
        var client = await _clientController.Call_CreateClientAsync(ClientControllerExtensions.GetDefaultClient(1), Contributor);
        var addedCors = await _clientCorsController.Call_AddClientCorsAsync(client.Id, corsOrigin, Contributor);

        // Act
        var deletedId = await _clientCorsController.Call_DeleteClientCorsAsync(addedCors.Id, Contributor);
        var updatedClient = await _clientController.Call_GetClientAsync(client.Id, Contributor);

        // Assert
        Assert.That(deletedId, Is.EqualTo(addedCors.Id));
        ClientCorsControllerExtensions.AssertClientDoesNotHaveCorsOrigin(updatedClient, corsOrigin);
    }

    [Test]
    public async Task DeleteClientCorsAsync_WithNonExistentCorsOrigin_ReturnsNotFound()
    {
        // Arrange
        var nonExistentId = 999;
        SetControllerContext(_clientCorsController, Contributor);

        // Act
        var response = await _clientCorsController.DeletePropertyByIdAsync(nonExistentId);

        // Assert
        Assert.That(response.Result, Is.TypeOf<NotFoundResult>());
    }

    [Test]
    public async Task AddClientCorsAsync_InvalidatesCache()
    {
        // Arrange
        var corsOrigin = "https://example.com";
        var client = await _clientController.Call_CreateClientAsync(ClientControllerExtensions.GetDefaultClient(1), Contributor);

        // Act
        await _clientCorsController.Call_AddClientCorsAsync(client.Id, corsOrigin, Contributor);

        // Assert
        await _clientCache.Received(1).RemoveAsync(client.ClientId);
    }

    [Test]
    public async Task DeleteClientCorsAsync_InvalidatesCache()
    {
        // Arrange
        var corsOrigin = "https://example.com";
        var client = await _clientController.Call_CreateClientAsync(ClientControllerExtensions.GetDefaultClient(1), Contributor);
        var addedCors = await _clientCorsController.Call_AddClientCorsAsync(client.Id, corsOrigin, Contributor);

        // Reset the mock to clear previous calls
        _clientCache.ClearReceivedCalls();
        _corsCache.ClearReceivedCalls();

        // Act
        await _clientCorsController.Call_DeleteClientCorsAsync(addedCors.Id, Contributor);

        // Assert
        await _clientCache.Received(1).RemoveAsync(client.ClientId);
        await _corsCache.Received(1).RemoveAsync(corsOrigin);
    }
}
