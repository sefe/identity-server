// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

using Microsoft.Extensions.DependencyInjection;
using NSubstitute;
using IdentityServer.Abstraction.Contracts;
using IdentityServer.Abstraction.Entities.IdentityServerConfig;
using IdentityServer.Abstraction.Exceptions;
using IdentityServer.AdminPortal.Server.Controllers;
using IdentityServer.AdminPortal.Test.Extensions;
using IdentityServer.Tests.Common;
using DataEntities = Duende.IdentityServer.EntityFramework.Entities;

namespace IdentityServer.AdminPortal.Test.Controller;

public class ClientScopeControllerTests : ControllerTestBase
{
    private ClientController _clientController;
    private ClientPropertyScopeController _clientScopeController;
    private ApiResourceController _apiResourceController;
    private ApiResourcePropertyScopeController _apiResourceScopeController;
    private ICache<DataEntities.Client> _clientCache;

    [SetUp]
    public async Task Setup()
    {
        _clientCache = Substitute.For<ICache<DataEntities.Client>>();

        var provider = IoC.GetProvider(sc =>
        {
            sc.AddScoped<ClientController>();
            sc.AddScoped<ClientPropertyScopeController>();
            sc.AddScoped<ApiResourceController>();
            sc.AddScoped<ApiResourcePropertyScopeController>();
            sc.ReplaceWithInstance(EverythingIsAllowed);
            sc.ReplaceWithInstance(_clientCache);
        });

        await Setup(provider);

        _clientController = provider.GetRequiredService<ClientController>();
        _clientScopeController = provider.GetRequiredService<ClientPropertyScopeController>();
        _apiResourceController = provider.GetRequiredService<ApiResourceController>();
        _apiResourceScopeController = provider.GetRequiredService<ApiResourcePropertyScopeController>();
    }

    [Test]
    public async Task Add_ApiScope_To_Client()
    {
        // Arrange
        var api = await _apiResourceController.Call_CreateApiResourceAsync(ApiResourceControllerExtensions.GetDefaultApiResource(1), Admin);
        var scopeDto = ApiResourceScopeControllerExtensions.NewScopeFor(api.Id, Guid.NewGuid().ToString());
        _ = await _apiResourceScopeController.Call_AddApiResourceScopeAsync(scopeDto, Admin);

        var client = await _clientController.Call_CreateClientAsync(ClientControllerExtensions.GetDefaultClient(1), Contributor);

        // Act
        var addedScope = await _clientScopeController.Call_AddClientScopeAsync(client.Id, scopeDto.Name, Contributor);
        var updatedClient = await _clientController.Call_GetClientAsync(client.Id, Contributor);

        // Assert
        ClientScopeControllerExtensions.AssertClientScopeIsValid(addedScope, client.Id, scopeDto.Name);
        ClientScopeControllerExtensions.AssertClientScopeHasApiScope(addedScope, scopeDto);
        ClientScopeControllerExtensions.AssertClientHasScope(updatedClient, scopeDto.Name);
    }

    [Test]
    public async Task Add_ApiScope_To_Client_Duplicate()
    {
        // Arrange
        var api = await _apiResourceController.Call_CreateApiResourceAsync(ApiResourceControllerExtensions.GetDefaultApiResource(1), Admin);
        var scopeDto = ApiResourceScopeControllerExtensions.NewScopeFor(api.Id, Guid.NewGuid().ToString());
        _ = await _apiResourceScopeController.Call_AddApiResourceScopeAsync(scopeDto, Admin);

        var client = await _clientController.Call_CreateClientAsync(ClientControllerExtensions.GetDefaultClient(1), Contributor);
        _ = await _clientScopeController.Call_AddClientScopeAsync(client.Id, scopeDto.Name, Contributor);

        // Act & Assert
        Assert.ThrowsAsync<EntityAlreadyExistsException>(() => _clientScopeController.Call_AddClientScopeAsync(client.Id, scopeDto.Name, Contributor));
    }

    [Test]
    public async Task Add_OidcScope_To_Client()
    {
        // Arrange
        var scope = OidcScopeNames.OidcStandardScopes[0].Name;
        var client = await _clientController.Call_CreateClientAsync(ClientControllerExtensions.GetDefaultClient(1), Contributor);

        // Act
        var addedScope = await _clientScopeController.Call_AddClientScopeAsync(client.Id, scope, Contributor);
        var updatedClient = await _clientController.Call_GetClientAsync(client.Id, Contributor);

        // Assert
        ClientScopeControllerExtensions.AssertClientScopeIsValid(addedScope, client.Id, scope);
        Assert.That(addedScope.ApiScope, Is.Null); //OIDC scopes are not related to API Scopes
        ClientScopeControllerExtensions.AssertClientHasScope(updatedClient, scope);
    }

    [Test]
    public async Task Add_OidcScope_To_Client_Duplicate()
    {
        // Arrange
        var scope = OidcScopeNames.OidcStandardScopes[0].Name;
        var client = await _clientController.Call_CreateClientAsync(ClientControllerExtensions.GetDefaultClient(1), Contributor);
        _ = await _clientScopeController.Call_AddClientScopeAsync(client.Id, scope, Contributor);

        // Act & Assert
        Assert.ThrowsAsync<EntityAlreadyExistsException>(() => _clientScopeController.Call_AddClientScopeAsync(client.Id, scope, Contributor));
    }
    [Test]
    public async Task AddClientScope_InvalidatesCache()
    {
        // Arrange
        var api = await _apiResourceController.Call_CreateApiResourceAsync(ApiResourceControllerExtensions.GetDefaultApiResource(1), Admin);
        var scopeDto = ApiResourceScopeControllerExtensions.NewScopeFor(api.Id, Guid.NewGuid().ToString());
        _ = await _apiResourceScopeController.Call_AddApiResourceScopeAsync(scopeDto, Admin);

        var client = await _clientController.Call_CreateClientAsync(ClientControllerExtensions.GetDefaultClient(1), Contributor);

        // Act
        await _clientScopeController.Call_AddClientScopeAsync(client.Id, scopeDto.Name, Contributor);

        // Assert
        await _clientCache.Received(1).RemoveAsync(client.ClientId);
    }

    [Test]
    public async Task Delete_Scope_From_Client()
    {
        // Arrange
        var api = await _apiResourceController.Call_CreateApiResourceAsync(ApiResourceControllerExtensions.GetDefaultApiResource(1), Admin);
        var scopeDto1 = ApiResourceScopeControllerExtensions.NewScopeFor(api.Id, Guid.NewGuid().ToString());
        var scopeDto2 = ApiResourceScopeControllerExtensions.NewScopeFor(api.Id, Guid.NewGuid().ToString());
        _ = await _apiResourceScopeController.Call_AddApiResourceScopeAsync(scopeDto1, Admin);
        _ = await _apiResourceScopeController.Call_AddApiResourceScopeAsync(scopeDto2, Admin);

        var client = await _clientController.Call_CreateClientAsync(ClientControllerExtensions.GetDefaultClient(1), Contributor);
        var addedScope1 = await _clientScopeController.Call_AddClientScopeAsync(client.Id, scopeDto1.Name, Contributor);
        _ = await _clientScopeController.Call_AddClientScopeAsync(client.Id, scopeDto2.Name, Contributor);

        // Act
        var deletedScopeId = await _clientScopeController.Call_DeleteClientScopeAsync(addedScope1.Id, Contributor);
        var updatedClient = await _clientController.Call_GetClientAsync(client.Id, Contributor);

        // Assert
        Assert.That(deletedScopeId, Is.EqualTo(addedScope1.Id));
        ClientScopeControllerExtensions.AssertClientHasScope(updatedClient, scopeDto2.Name);
    }

    [Test]
    public async Task DeleteApiScope_IfUsedByClient_Fails()
    {
        // Arrange
        var api = await _apiResourceController.Call_CreateApiResourceAsync(ApiResourceControllerExtensions.GetDefaultApiResource(1), Admin);
        var scopeDto = ApiResourceScopeControllerExtensions.NewScopeFor(api.Id, Guid.NewGuid().ToString());
        var createdScope = await _apiResourceScopeController.Call_AddApiResourceScopeAsync(scopeDto, Admin);

        var client = await _clientController.Call_CreateClientAsync(ClientControllerExtensions.GetDefaultClient(1), Contributor);
        _ = await _clientScopeController.Call_AddClientScopeAsync(client.Id, scopeDto.Name, Contributor);

        // Act & Assert
        Assert.ThrowsAsync<EntityReferenceException>(() =>
            _apiResourceScopeController.Call_DeleteApiResourceScopeAsync(createdScope.Id, Admin));
    }

    [Test]
    public async Task Delete_OpenIdScope_ShouldSetAllowOfflineAccessToFalse()
    {
        // Arrange
        var client = await _clientController.Call_CreateClientAsync(ClientControllerExtensions.GetDefaultClient(1), Contributor);
        var addedScope1 = _ = await _clientScopeController.Call_AddClientScopeAsync(client.Id, OidcScopeNames.OpenIdScope, Contributor);
        _ = await _clientController.Call_UpdateClientAsync(new Abstraction.DTO.Clients.ClientDtoUpdate()
        {
            Id = client.Id,
            AllowOfflineAccess = true
        }, Contributor);

        // Act
        var deletedScopeId = await _clientScopeController.Call_DeleteClientScopeAsync(addedScope1.Id, Contributor);
        var updatedClient = await _clientController.Call_GetClientAsync(client.Id, Contributor);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(deletedScopeId, Is.EqualTo(addedScope1.Id));
            Assert.That(updatedClient.AllowOfflineAccess, Is.False);
        }
    }

    [Test]
    public async Task DeleteClientScope_InvalidatesCache()
    {
        // Arrange
        var api = await _apiResourceController.Call_CreateApiResourceAsync(ApiResourceControllerExtensions.GetDefaultApiResource(1), Admin);
        var scopeDto = ApiResourceScopeControllerExtensions.NewScopeFor(api.Id, Guid.NewGuid().ToString());
        _ = await _apiResourceScopeController.Call_AddApiResourceScopeAsync(scopeDto, Admin);

        var client = await _clientController.Call_CreateClientAsync(ClientControllerExtensions.GetDefaultClient(1), Contributor);
        var addedScope = await _clientScopeController.Call_AddClientScopeAsync(client.Id, scopeDto.Name, Contributor);

        // Reset the mock to clear previous calls
        _clientCache.ClearReceivedCalls();

        // Act
        await _clientScopeController.Call_DeleteClientScopeAsync(addedScope.Id, Contributor);

        // Assert
        await _clientCache.Received(1).RemoveAsync(client.ClientId);
    }

    [Test]
    public async Task ClientScopeShoulBeDisabled_If_ApiScopeIsDisabled()
    {
        // Arrange
        var api = await _apiResourceController.Call_CreateApiResourceAsync(ApiResourceControllerExtensions.GetDefaultApiResource(1), Admin);
        var scopeDto = ApiResourceScopeControllerExtensions.NewScopeFor(api.Id, Guid.NewGuid().ToString());
        var createdScope = await _apiResourceScopeController.Call_AddApiResourceScopeAsync(scopeDto, Admin);

        var client = await _clientController.Call_CreateClientAsync(ClientControllerExtensions.GetDefaultClient(1), Contributor);
        var addedScope = await _clientScopeController.Call_AddClientScopeAsync(client.Id, scopeDto.Name, Contributor);

        await _apiResourceScopeController.Call_UpdateApiResourceScopeAsync(
            new Abstraction.DTO.ApiResources.ApiResourcePropertyScopeDtoUpdate { Id = createdScope.Id, Enabled = false }, Admin);

        // Act
        var updatedClient = await _clientController.Call_GetClientAsync(client.Id, Contributor);

        // Assert
        ClientScopeControllerExtensions.AssertClientScopeIsValid(addedScope, client.Id, scopeDto.Name);
        ClientScopeControllerExtensions.AssertClientScopeHasApiScope(addedScope, scopeDto);
        ClientScopeControllerExtensions.AssertClientHasScope(updatedClient, scopeDto.Name);
        using (Assert.EnterMultipleScope())
        {
            Assert.That(updatedClient.AllowedScopes.First(s => s.Id == createdScope.Id).ApiScope.Enabled, Is.False);
            Assert.That(updatedClient.AllowedScopes.First(s => s.Id == createdScope.Id).ApiResourceEnabled, Is.True);
        }
    }

    [Test]
    public async Task ClientScopeShoulBeDisabled_If_ApiResourceIsDisabled()
    {
        // Arrange
        var api = await _apiResourceController.Call_CreateApiResourceAsync(ApiResourceControllerExtensions.GetDefaultApiResource(1), Admin);
        var scopeDto = ApiResourceScopeControllerExtensions.NewScopeFor(api.Id, Guid.NewGuid().ToString());
        var createdScope = await _apiResourceScopeController.Call_AddApiResourceScopeAsync(scopeDto, Admin);

        var client = await _clientController.Call_CreateClientAsync(ClientControllerExtensions.GetDefaultClient(1), Contributor);
        var addedScope = await _clientScopeController.Call_AddClientScopeAsync(client.Id, scopeDto.Name, Contributor);

        await _apiResourceController.Call_UpdateApiResourceAsync(
            new Abstraction.DTO.ApiResources.ApiResourceDtoUpdate { Id = api.Id, Enabled = false }, Admin);

        // Act
        var updatedClient = await _clientController.Call_GetClientAsync(client.Id, Contributor);

        // Assert
        ClientScopeControllerExtensions.AssertClientScopeIsValid(addedScope, client.Id, scopeDto.Name);
        ClientScopeControllerExtensions.AssertClientScopeHasApiScope(addedScope, scopeDto);
        ClientScopeControllerExtensions.AssertClientHasScope(updatedClient, scopeDto.Name);
        using (Assert.EnterMultipleScope())
        {
            Assert.That(updatedClient.AllowedScopes.First(s => s.Id == createdScope.Id).ApiScope.Enabled, Is.True);
            Assert.That(updatedClient.AllowedScopes.First(s => s.Id == createdScope.Id).ApiResourceEnabled, Is.False);
        }
    }
}
