// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

using Duende.IdentityServer.Models;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Extensions.DependencyInjection;
using NSubstitute;
using IdentityServer.Abstraction.Contracts;
using IdentityServer.Abstraction.Exceptions;
using IdentityServer.AdminPortal.Server.Controllers;
using IdentityServer.AdminPortal.Test.Extensions;
using IdentityServer.Data.DuendeEntityExtensions;
using IdentityServer.Tests.Common;
using DataEntities = Duende.IdentityServer.EntityFramework.Entities;

namespace IdentityServer.AdminPortal.Test.Controller;

public class ClientSecretControllerTests : ControllerTestBase
{
    private ClientController _clientController;
    private ClientPropertySecretController _secretController;
    private IStorage<ClientSecretExt> _clientSecretStorage;
    private ICache<DataEntities.Client> _clientCache;

    [SetUp]
    public async Task Setup()
    {
        _clientCache = Substitute.For<ICache<DataEntities.Client>>();

        var provider = IoC.GetProvider(sc =>
        {
            sc.AddScoped<ClientController>();
            sc.AddScoped<ClientPropertySecretController>();
            sc.ReplaceWithInstance(EverythingIsAllowed);
            sc.ReplaceWithInstance(_clientCache);
        });

        await Setup(provider);

        _clientController = provider.GetRequiredService<ClientController>();
        _secretController = provider.GetRequiredService<ClientPropertySecretController>();
        _clientSecretStorage = provider.GetRequiredService<IStorage<ClientSecretExt>>();
    }

    [Test]
    public async Task Create_Secret_Invalid_Client_Fail()
    {
        var newSecret = ClientSecretControllerExtensions.GetDefaultClientSecretFor(0);

        SetControllerContext(_secretController, Admin);
        var response = await _secretController.CreatePropertyAsync(newSecret);
        Assert.That(response.Result, Is.TypeOf<BadRequestObjectResult>());
    }

    [Test]
    public void Create_Secret_Missing_Client_Fail()
    {
        var newSecret = ClientSecretControllerExtensions.GetDefaultClientSecretFor(999);

        Assert.ThrowsAsync<EntityNotFoundException>(() => _secretController.Call_CreateSecretAsync(newSecret, Admin));
    }

    [Test]
    public async Task Created_Secret_Visible_In_Client()
    {
        var createdClient = await _clientController.Call_CreateClientAsync(ClientControllerExtensions.GetDefaultClient(1), Admin);
        var newSecret = ClientSecretControllerExtensions.GetDefaultClientSecretFor(createdClient.Id);
        _ = await _secretController.Call_CreateSecretAsync(newSecret, Admin);

        var retrievedClient = await _clientController.Call_GetClientAsync(createdClient.Id, Admin);

        Assert.That(retrievedClient.ClientSecrets, Has.Count.EqualTo(1));
        var retrievedSecret = retrievedClient.ClientSecrets[0];
        using (Assert.EnterMultipleScope())
        {
            Assert.That(retrievedSecret.Id, Is.Not.Zero);
            Assert.That(retrievedSecret.ClientId, Is.EqualTo(createdClient.Id));
            Assert.That(retrievedSecret.Description, Is.EqualTo(newSecret.Description));
            Assert.That(retrievedSecret.Expiration, Is.Not.Null);
            Assert.That(retrievedSecret.Expiration, Is.GreaterThan(DateTime.UtcNow.AddYears(1)));
        }
    }

    [Test]
    public async Task Created_Secret_Matches_Saved_Hash()
    {
        var createdClient = await _clientController.Call_CreateClientAsync(ClientControllerExtensions.GetDefaultClient(1), Admin);
        var newSecret = ClientSecretControllerExtensions.GetDefaultClientSecretFor(createdClient.Id);
        var createdSecret = await _secretController.Call_CreateSecretAsync(newSecret, Admin);

        var retrievedSecret = await _clientSecretStorage.GetByIdAsync(createdSecret.Id);

        using (Assert.EnterMultipleScope())
        {
            Assert.That(retrievedSecret.Value, Is.EqualTo(createdSecret.Value.Sha256()));
        }
    }

    [Test]
    public async Task CreateSecret_WithSameDescription_Fails()
    {
        var createdClient = await _clientController.Call_CreateClientAsync(ClientControllerExtensions.GetDefaultClient(1), Admin);
        var newSecret = ClientSecretControllerExtensions.GetDefaultClientSecretFor(createdClient.Id);
        _ = await _secretController.Call_CreateSecretAsync(newSecret, Admin);

        Assert.ThrowsAsync<EntityAlreadyExistsException>(() => _secretController.Call_CreateSecretAsync(newSecret, Admin));
    }

    [Test]
    public async Task CreateSecret_InvalidatesClientCache()
    {
        // Arrange
        var createdClient = await _clientController.Call_CreateClientAsync(ClientControllerExtensions.GetDefaultClient(1), Admin);
        var newSecret = ClientSecretControllerExtensions.GetDefaultClientSecretFor(createdClient.Id);

        // Act
        await _secretController.Call_CreateSecretAsync(newSecret, Admin);

        // Assert
        await _clientCache.Received(1).RemoveAsync(createdClient.ClientId);
    }

    [Test]
    public async Task DeleteSecret_InvalidatesClientCache()
    {
        // Arrange
        var createdClient = await _clientController.Call_CreateClientAsync(ClientControllerExtensions.GetDefaultClient(1), Admin);
        var newSecret = ClientSecretControllerExtensions.GetDefaultClientSecretFor(createdClient.Id);
        var createdSecret = await _secretController.Call_CreateSecretAsync(newSecret, Admin);
        _clientCache.ClearReceivedCalls();

        // Act
        await _secretController.Call_DeleteSecretAsync(createdSecret.Id, Admin);

        // Assert
        await _clientCache.Received(1).RemoveAsync(createdClient.ClientId);
    }
}
