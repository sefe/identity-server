// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

using Microsoft.AspNetCore.Mvc;
using Microsoft.Extensions.DependencyInjection;
using NSubstitute;
using IdentityServer.Abstraction.Contracts;
using IdentityServer.Abstraction.DTO.ApiResources;
using IdentityServer.Abstraction.Exceptions;
using IdentityServer.AdminPortal.Server.Controllers;
using IdentityServer.AdminPortal.Test.Extensions;
using IdentityServer.Tests.Common;
using DataEntities = Duende.IdentityServer.EntityFramework.Entities;

namespace IdentityServer.AdminPortal.Test.Controller;

public class ApiResourceScopeControllerTests : ControllerTestBase
{
    private ApiResourceController _apiResourceController;
    private ApiResourcePropertyScopeController _apiResourceScopeController;
    private ClientController _clientController;
    private ClientPropertyScopeController _clientScopeController;
    private ICache<DataEntities.ApiResource> _apiCache;
    private ICache<DataEntities.ApiScope> _scopeCache;
    private ICache<DataEntities.Client> _clientCache;

    [SetUp]
    public async Task Setup()
    {
        _apiCache = Substitute.For<ICache<DataEntities.ApiResource>>();
        _scopeCache = Substitute.For<ICache<DataEntities.ApiScope>>();
        _clientCache = Substitute.For<ICache<DataEntities.Client>>();

        var provider = IoC.GetProvider(sc =>
        {
            sc.AddScoped<ApiResourceController>();
            sc.AddScoped<ApiResourcePropertyScopeController>();
            sc.AddScoped<ClientController>();
            sc.AddScoped<ClientPropertyScopeController>();
            sc.ReplaceWithInstance(EverythingIsAllowed);
            sc.ReplaceWithInstance(_apiCache);
            sc.ReplaceWithInstance(_scopeCache);
            sc.ReplaceWithInstance(_clientCache);
        });

        await Setup(provider);

        _apiResourceController = provider.GetRequiredService<ApiResourceController>();
        _apiResourceScopeController = provider.GetRequiredService<ApiResourcePropertyScopeController>();
        _clientController = provider.GetRequiredService<ClientController>();
        _clientScopeController = provider.GetRequiredService<ClientPropertyScopeController>();
    }

    [Test]
    public async Task Create_WithInvalidApiResourceId_Fails()
    {
        // Arrange 
        var newScope = ApiResourceScopeControllerExtensions.NewScopeFor(0, Guid.NewGuid().ToString());
        SetControllerContext(_apiResourceScopeController, Admin);

        // Act
        var response = await _apiResourceScopeController.CreatePropertyAsync(newScope);

        // Assert
        Assert.That(response.Result, Is.TypeOf<BadRequestObjectResult>());
    }

    [Test]
    public void Create_IfMissingApiResource_Fails()
    {
        // Arrange 
        var newScope = ApiResourceScopeControllerExtensions.NewScopeFor(999, Guid.NewGuid().ToString());

        // Act & Assert
        Assert.ThrowsAsync<EntityNotFoundException>(() => _apiResourceScopeController.Call_AddApiResourceScopeAsync(newScope, Admin));
    }

    [Test]
    public async Task Create_IfValidName_ReturnsCreatedScopeAndPersistsInApiResource()
    {
        // Arrange
        var createdApiResource = await _apiResourceController.Call_CreateApiResourceAsync(ApiResourceControllerExtensions.GetDefaultApiResource(1), Admin);
        string scopeName = Guid.NewGuid().ToString();
        string expectedScopeName = $"{createdApiResource.Name}.{scopeName}";
        var newScope = ApiResourceScopeControllerExtensions.NewScopeFor(createdApiResource.Id, scopeName);

        // Act
        var result = await _apiResourceScopeController.Call_AddApiResourceScopeAsync(newScope, Admin);

        // Assert
        var retrievedApiResource = await _apiResourceController.Call_GetApiResourceAsync(createdApiResource.Id, Admin);
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result, Is.Not.Null);
            Assert.That(retrievedApiResource.Scopes, Has.Count.EqualTo(1));
        }

        var retrievedScope = retrievedApiResource.Scopes[0];
        using (Assert.EnterMultipleScope())
        {
            Assert.That(retrievedScope.Id, Is.Not.Zero);
            Assert.That(retrievedScope.ApiResourceId, Is.EqualTo(createdApiResource.Id));
            Assert.That(retrievedScope.ApiScope.Name, Is.EqualTo(expectedScopeName));
            Assert.That(retrievedScope.ApiScope.Description, Is.EqualTo(newScope.Description));

            Assert.That(result.Id, Is.Not.Zero);
            Assert.That(result.ApiResourceId, Is.EqualTo(createdApiResource.Id));
            Assert.That(result.ApiScope.Name, Is.EqualTo(expectedScopeName));
            Assert.That(result.ApiScope.Description, Is.EqualTo(newScope.Description));
        }
    }

    [Test]
    public async Task Create_WithDuplicateName_Fails()
    {
        // Arrange
        var createdApiResource = await _apiResourceController.Call_CreateApiResourceAsync(ApiResourceControllerExtensions.GetDefaultApiResource(1), Admin);
        string scopeName = Guid.NewGuid().ToString();
        var newScope = ApiResourceScopeControllerExtensions.NewScopeFor(createdApiResource.Id, scopeName);
        var sameScope = ApiResourceScopeControllerExtensions.NewScopeFor(createdApiResource.Id, scopeName);

        // Act & Assert
        await _apiResourceScopeController.Call_AddApiResourceScopeAsync(newScope, Admin);
        Assert.ThrowsAsync<EntityAlreadyExistsException>(() => _apiResourceScopeController.Call_AddApiResourceScopeAsync(sameScope, Admin));
    }

    [Test]
    public async Task CreateScope_InvalidatesApiResourceCache()
    {
        // Arrange
        var createdApiResource = await _apiResourceController.Call_CreateApiResourceAsync(ApiResourceControllerExtensions.GetDefaultApiResource(1), Admin);
        var newScope = ApiResourceScopeControllerExtensions.NewScopeFor(createdApiResource.Id, Guid.NewGuid().ToString());

        // Act
        await _apiResourceScopeController.Call_AddApiResourceScopeAsync(newScope, Admin);

        // Assert
        await _apiCache.Received(1).RemoveAsync(createdApiResource.Name);
    }

    [Test]
    public async Task Update_IfNullParams_Fails()
    {
        // Arrange
        var createdApiResource = await _apiResourceController.Call_CreateApiResourceAsync(ApiResourceControllerExtensions.GetDefaultApiResource(1), Admin);
        var newScope = ApiResourceScopeControllerExtensions.NewScopeFor(createdApiResource.Id, Guid.NewGuid().ToString());
        var createdScope = await _apiResourceScopeController.Call_AddApiResourceScopeAsync(newScope, Admin);
        var updateDto = new ApiResourcePropertyScopeDtoUpdate()
        {
            Id = createdScope.Id,
            // no updates provided
        };

        // Act & Assert
        Assert.ThrowsAsync<EntityValidationException>(() => _apiResourceScopeController.Call_UpdateApiResourceScopeAsync(updateDto, Admin));
    }

    [Test]
    public async Task Update_WithNewDisplayName_Succeeds()
    {
        // Arrange
        var createdApiResource = await _apiResourceController.Call_CreateApiResourceAsync(ApiResourceControllerExtensions.GetDefaultApiResource(1), Admin);
        // valid name should start with the resource id - handled by helpers
        var newScope = ApiResourceScopeControllerExtensions.NewScopeFor(createdApiResource.Id, Guid.NewGuid().ToString());
        var createdScope = await _apiResourceScopeController.Call_AddApiResourceScopeAsync(newScope, Admin);

        // Act
        var updateDto = new ApiResourcePropertyScopeDtoUpdate()
        {
            Id = createdScope.Id,
            DisplayName = Guid.NewGuid().ToString()
        };
        var result = await _apiResourceScopeController.Call_UpdateApiResourceScopeAsync(updateDto, Admin);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result.Id, Is.EqualTo(createdScope.Id));
            Assert.That(result.ApiResourceId, Is.EqualTo(createdApiResource.Id));
            Assert.That(result.ApiScope.DisplayName, Is.EqualTo(updateDto.DisplayName));
            Assert.That(result.ApiScope.Description, Is.EqualTo(newScope.Description));
            Assert.That(result.ApiScope.Enabled, Is.EqualTo(newScope.Enabled));
            Assert.That(result.ApiScope.Required, Is.EqualTo(newScope.Required));
        }
    }

    [Test]
    public async Task Update_IfEmptyDisplayName_Fails()
    {
        // Arrange
        var createdApiResource = await _apiResourceController.Call_CreateApiResourceAsync(ApiResourceControllerExtensions.GetDefaultApiResource(1), Admin);
        var newScope = ApiResourceScopeControllerExtensions.NewScopeFor(createdApiResource.Id, Guid.NewGuid().ToString());
        var createdScope = await _apiResourceScopeController.Call_AddApiResourceScopeAsync(newScope, Admin);
        var updateDto = new ApiResourcePropertyScopeDtoUpdate()
        {
            Id = createdScope.Id,
            DisplayName = ""
        };

        // Act & Assert
        Assert.ThrowsAsync<EntityValidationException>(() => _apiResourceScopeController.Call_UpdateApiResourceScopeAsync(updateDto, Admin));
    }

    [Test]
    public async Task Update_WithNewDescription_Succeeds()
    {
        // Arrange 
        var createdApiResource = await _apiResourceController.Call_CreateApiResourceAsync(ApiResourceControllerExtensions.GetDefaultApiResource(1), Admin);
        var newScope = ApiResourceScopeControllerExtensions.NewScopeFor(createdApiResource.Id, Guid.NewGuid().ToString());
        var createdScope = await _apiResourceScopeController.Call_AddApiResourceScopeAsync(newScope, Admin);

        var newDescription = Guid.NewGuid().ToString();
        var updateDto = new ApiResourcePropertyScopeDtoUpdate()
        {
            Id = createdScope.Id,
            Description = newDescription
        };

        // Act 
        var result = await _apiResourceScopeController.Call_UpdateApiResourceScopeAsync(updateDto, Admin);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result.Id, Is.EqualTo(createdScope.Id));
            Assert.That(result.ApiResourceId, Is.EqualTo(createdApiResource.Id));
            Assert.That(result.ApiScope.Description, Is.EqualTo(newDescription));
            Assert.That(result.ApiScope.DisplayName, Is.EqualTo(newScope.DisplayName));
            Assert.That(result.ApiScope.Enabled, Is.EqualTo(newScope.Enabled));
            Assert.That(result.ApiScope.Required, Is.EqualTo(newScope.Required));
        }
    }

    [Test]
    public async Task Update_WithNewEnabledProperty_Succeeds()
    {
        // Arrange 
        var createdApiResource = await _apiResourceController.Call_CreateApiResourceAsync(ApiResourceControllerExtensions.GetDefaultApiResource(1), Admin);
        var newScope = ApiResourceScopeControllerExtensions.NewScopeFor(createdApiResource.Id, Guid.NewGuid().ToString());
        newScope.Enabled = false;
        var createdScope = await _apiResourceScopeController.Call_AddApiResourceScopeAsync(newScope, Admin);

        var updateDto = new ApiResourcePropertyScopeDtoUpdate()
        {
            Id = createdScope.Id,
            Enabled = true
        };

        // Act 
        var result = await _apiResourceScopeController.Call_UpdateApiResourceScopeAsync(updateDto, Admin);

        // Assert 
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result.Id, Is.EqualTo(createdScope.Id));
            Assert.That(result.ApiResourceId, Is.EqualTo(createdApiResource.Id));
            Assert.That(result.ApiScope.Enabled, Is.EqualTo(updateDto.Enabled));
            Assert.That(result.ApiScope.DisplayName, Is.EqualTo(newScope.DisplayName));
            Assert.That(result.ApiScope.Description, Is.EqualTo(newScope.Description));
            Assert.That(result.ApiScope.Required, Is.EqualTo(newScope.Required));
        }
    }

    [Test]
    public async Task Update_WithNewRequiredProperty_Succeeds()
    {
        // Arrange 
        var createdApiResource = await _apiResourceController.Call_CreateApiResourceAsync(ApiResourceControllerExtensions.GetDefaultApiResource(1), Admin);
        var newScope = ApiResourceScopeControllerExtensions.NewScopeFor(createdApiResource.Id, Guid.NewGuid().ToString());
        newScope.Required = true;
        var createdScope = await _apiResourceScopeController.Call_AddApiResourceScopeAsync(newScope, Admin);

        var updateDto = new ApiResourcePropertyScopeDtoUpdate()
        {
            Id = createdScope.Id,
            Required = false
        };

        // Act
        var result = await _apiResourceScopeController.Call_UpdateApiResourceScopeAsync(updateDto, Admin);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result.Id, Is.EqualTo(createdScope.Id));
            Assert.That(result.ApiResourceId, Is.EqualTo(createdApiResource.Id));
            Assert.That(result.ApiScope.Required, Is.EqualTo(updateDto.Required));
            Assert.That(result.ApiScope.DisplayName, Is.EqualTo(newScope.DisplayName));
            Assert.That(result.ApiScope.Description, Is.EqualTo(newScope.Description));
            Assert.That(result.ApiScope.Enabled, Is.EqualTo(newScope.Enabled));
        }
    }

    [Test]
    public async Task UpdateScope_InvalidatesScopeCache()
    {
        // Arrange
        var createdApiResource = await _apiResourceController.Call_CreateApiResourceAsync(ApiResourceControllerExtensions.GetDefaultApiResource(1), Admin);
        var newScope = ApiResourceScopeControllerExtensions.NewScopeFor(createdApiResource.Id, Guid.NewGuid().ToString());
        var createdScope = await _apiResourceScopeController.Call_AddApiResourceScopeAsync(newScope, Admin);
        var updateDto = new ApiResourcePropertyScopeDtoUpdate()
        {
            Id = createdScope.Id,
            DisplayName = "Updated Display Name"
        };

        // Act
        await _apiResourceScopeController.Call_UpdateApiResourceScopeAsync(updateDto, Admin);

        // Assert
        await _scopeCache.Received(1).RemoveAsync(newScope.Name);
    }

    [Test]
    public async Task Delete_IfExistsAndUnsed_Succeeds()
    {
        // Arrange 
        var createdApiResource = await _apiResourceController.Call_CreateApiResourceAsync(ApiResourceControllerExtensions.GetDefaultApiResource(1), Admin);
        var newScope = ApiResourceScopeControllerExtensions.NewScopeFor(createdApiResource.Id, Guid.NewGuid().ToString());
        newScope.Required = true;
        var createdScope = await _apiResourceScopeController.Call_AddApiResourceScopeAsync(newScope, Admin);

        // Act
        var result = await _apiResourceScopeController.Call_DeleteApiResourceScopeAsync(createdScope.Id, Admin);

        // Assert
        Assert.That(result, Is.EqualTo(createdScope.Id));
    }

    [Test]
    public void Delete_WithInvalidId_Fails()
    {
        // Arrange 
        SetControllerContext(_apiResourceScopeController, Contributor);

        // Act & Assert
        Assert.ThrowsAsync<EntityNotFoundException>(() => _apiResourceScopeController.DeletePropertyByIdAsync(999));
    }

    [Test]
    public async Task DeleteScope_InvalidatesApiResourceAndScopeCache()
    {
        // Arrange
        var createdApiResource = await _apiResourceController.Call_CreateApiResourceAsync(ApiResourceControllerExtensions.GetDefaultApiResource(1), Admin);
        var newScope = ApiResourceScopeControllerExtensions.NewScopeFor(createdApiResource.Id, Guid.NewGuid().ToString());
        var createdScope = await _apiResourceScopeController.Call_AddApiResourceScopeAsync(newScope, Admin);

        // Reset the mock to clear previous calls
        _apiCache.ClearReceivedCalls();
        _scopeCache.ClearReceivedCalls();

        // Act
        await _apiResourceScopeController.Call_DeleteApiResourceScopeAsync(createdScope.Id, Admin);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            await _apiCache.Received(1).RemoveAsync(createdApiResource.Name);
            await _scopeCache.Received(1).RemoveAsync(newScope.Name);
        }
    }

    [Test]
    public async Task Create_IfValidName_ReturnsApiScopeWithClientCountZero()
    {
        // Arrange
        var createdApiResource = await _apiResourceController.Call_CreateApiResourceAsync(ApiResourceControllerExtensions.GetDefaultApiResource(1), Admin);
        string scopeName = Guid.NewGuid().ToString();
        var newScope = ApiResourceScopeControllerExtensions.NewScopeFor(createdApiResource.Id, scopeName);

        // Act
        var result = await _apiResourceScopeController.Call_AddApiResourceScopeAsync(newScope, Admin);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result.ApiScope, Is.Not.Null);
            Assert.That(result.ApiScope.ClientCount, Is.Zero);
        }
    }

    [Test]
    public async Task Update_ReturnsApiScopeWithCorrectClientCount()
    {
        // Arrange
        var createdApiResource = await _apiResourceController.Call_CreateApiResourceAsync(ApiResourceControllerExtensions.GetDefaultApiResource(1), Admin);
        var newScope = ApiResourceScopeControllerExtensions.NewScopeFor(createdApiResource.Id, Guid.NewGuid().ToString());
        var createdScope = await _apiResourceScopeController.Call_AddApiResourceScopeAsync(newScope, Admin);

        // Add a client using this scope
        var client = await _clientController.Call_CreateClientAsync(ClientControllerExtensions.GetDefaultClient(1), Admin);
        await _clientScopeController.Call_AddClientScopeAsync(client.Id, newScope.Name, Admin);

        var updateDto = new ApiResourcePropertyScopeDtoUpdate()
        {
            Id = createdScope.Id,
            DisplayName = "Updated Display Name"
        };

        // Act
        var result = await _apiResourceScopeController.Call_UpdateApiResourceScopeAsync(updateDto, Admin);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result.ApiScope, Is.Not.Null);
            Assert.That(result.ApiScope.ClientCount, Is.EqualTo(1));
        }
    }

    [Test]
    public async Task Update_WithMultipleClients_ReturnsApiScopeWithCorrectClientCount()
    {
        // Arrange
        var createdApiResource = await _apiResourceController.Call_CreateApiResourceAsync(ApiResourceControllerExtensions.GetDefaultApiResource(1), Admin);
        var newScope = ApiResourceScopeControllerExtensions.NewScopeFor(createdApiResource.Id, Guid.NewGuid().ToString());
        var createdScope = await _apiResourceScopeController.Call_AddApiResourceScopeAsync(newScope, Admin);

        // Add multiple clients using this scope
        var client1 = await _clientController.Call_CreateClientAsync(ClientControllerExtensions.GetDefaultClient(1), Admin);
        var client2 = await _clientController.Call_CreateClientAsync(ClientControllerExtensions.GetDefaultClient(1), Admin);
        var client3 = await _clientController.Call_CreateClientAsync(ClientControllerExtensions.GetDefaultClient(1), Admin);
        await _clientScopeController.Call_AddClientScopeAsync(client1.Id, newScope.Name, Admin);
        await _clientScopeController.Call_AddClientScopeAsync(client2.Id, newScope.Name, Admin);
        await _clientScopeController.Call_AddClientScopeAsync(client3.Id, newScope.Name, Admin);

        var updateDto = new ApiResourcePropertyScopeDtoUpdate()
        {
            Id = createdScope.Id,
            Description = "Updated Description"
        };

        // Act
        var result = await _apiResourceScopeController.Call_UpdateApiResourceScopeAsync(updateDto, Admin);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result.ApiScope, Is.Not.Null);
            Assert.That(result.ApiScope.ClientCount, Is.EqualTo(3));
        }
    }
}
