using Microsoft.AspNetCore.Mvc;
using Microsoft.Extensions.DependencyInjection;
using NSubstitute;
using System.Security.Claims;
using IdentityServer.Abstraction.Contracts;
using IdentityServer.Abstraction.Contracts.MicrosoftGraph;
using IdentityServer.Abstraction.DTO.ApiResources;
using IdentityServer.Abstraction.DTO.Clients;
using IdentityServer.Abstraction.Entities.IdentityServerConfig;
using IdentityServer.Abstraction.Entities.IdentityServerConfig.SystemPermissions;
using IdentityServer.Abstraction.Exceptions;
using IdentityServer.AdminPortal.Server.Controllers;
using IdentityServer.AdminPortal.Test.Extensions;
using IdentityServer.Tests.Common;
using DataEntities = Duende.IdentityServer.EntityFramework.Entities;

namespace IdentityServer.AdminPortal.Test.Controller;

public class ClientControllerTests : ControllerTestBase
{
    private ClientController _clientController;
    private ApiResourceController _apiResourceController;
    private ApiResourcePropertyRoleController _apiResourceRoleController;
    private ApiResourcePropertyRoleMappingController _roleMappingController;
    private ClientPropertySecretController _clientSecretController;
    private ClientPropertyScopeController _clientScopeController;
    private ApiResourcePropertyScopeController _apiResourceScopeController;
    private ICache<DataEntities.Client> _clientCache;
    private IClientAuditService _clientAuditService;

    private readonly IEntraGroupService _entraGroupService = Substitute.For<IEntraGroupService>();
    private readonly IEntraUserService _entraUserService = Substitute.For<IEntraUserService>();

    [SetUp]
    public async Task Setup()
    {
        _clientCache = Substitute.For<ICache<DataEntities.Client>>();

        var provider = IoC.GetProvider(sc =>
        {
            sc.AddScoped<ClientController>();
            sc.AddScoped<ApiResourceController>();
            sc.AddScoped<ApiResourcePropertyRoleController>();
            sc.AddScoped<ApiResourcePropertyRoleMappingController>();
            sc.AddScoped<ClientPropertySecretController>();
            sc.AddScoped<ClientPropertyScopeController>();
            sc.AddScoped<ApiResourcePropertyScopeController>();
            sc.ReplaceWithInstance(EverythingIsAllowed);
            sc.ReplaceWithInstance(_clientCache);

            sc.AddSingleton(_entraGroupService);
            sc.AddSingleton(_entraUserService);
        });

        await Setup(provider);

        _clientController = provider.GetRequiredService<ClientController>();
        _apiResourceController = provider.GetRequiredService<ApiResourceController>();
        _apiResourceRoleController = provider.GetRequiredService<ApiResourcePropertyRoleController>();
        _roleMappingController = provider.GetRequiredService<ApiResourcePropertyRoleMappingController>();
        _clientSecretController = provider.GetRequiredService<ClientPropertySecretController>();
        _clientScopeController = provider.GetRequiredService<ClientPropertyScopeController>();
        _apiResourceScopeController = provider.GetRequiredService<ApiResourcePropertyScopeController>();
        _clientAuditService = provider.GetRequiredService<IClientAuditService>();
    }

    [Test]
    public async Task CreateClientAsync_WithValidClient_ReturnsCreatedClient()
    {
        // Arrange
        var clientDtoCreate = ClientControllerExtensions.GetDefaultClient(1);

        // Act
        var createdClient = await _clientController.Call_CreateClientAsync(clientDtoCreate, Admin);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(createdClient.Id, Is.EqualTo(1));
            Assert.That(createdClient.ClientSecrets, Has.Count.Zero);
            Assert.That(createdClient.AccessLevel, Is.EqualTo(SystemPermissionRoleType.Writer));
            Assert.That(createdClient.AllowedGrantTypes, Has.Count.EqualTo(clientDtoCreate.AllowedGrantTypes.Count));
            Assert.That(createdClient.AllowedGrantTypes[0].GrantType, Is.EqualTo(clientDtoCreate.AllowedGrantTypes.First()));
        }
    }

    [Test]
    public async Task CreateClientAsync_WithExistingName_ThrowsEntityAlreadyExistsException()
    {
        // Arrange
        var client = ClientControllerExtensions.GetDefaultClient(1);
        _ = await _clientController.Call_CreateClientAsync(client, Admin);

        // Act & Assert
        Assert.ThrowsAsync<EntityAlreadyExistsException>(() => _clientController.Call_CreateClientAsync(client, Admin));
    }

    [Test]
    public async Task DeleteClientAsync_WhenRoleMappingsExist_ThrowsEntityReferenceException()
    {
        // Arrange
        var createdClient = await _clientController.Call_CreateClientAsync(ClientControllerExtensions.GetDefaultClient(1), Admin);
        var api = await _apiResourceController.Call_CreateApiResourceAsync(ApiResourceControllerExtensions.GetDefaultApiResource(1), Admin);
        var role = await _apiResourceRoleController.Call_AddApiResourceRoleAsync(api.Id, "TestRole", Admin);
        await _roleMappingController.CreatePropertyAsync(new ApiResourcePropertyRoleMappingDtoCreate
        {
            ApiResourceId = api.Id,
            ApiResourceRoleId = role.Id,
            MappingType = RoleMapType.ClientId,
            Value = createdClient.ClientId,
        });

        // Act & Assert
        Assert.ThrowsAsync<EntityReferenceException>(() => _clientController.Call_DeleteClientAsync(createdClient.Id, Admin));
    }

    [Test]
    public async Task DeleteClientAsync_WithNestedEntities_ExecutesSuccessfully()
    {
        // Arrange
        var createdClient = await _clientController.Call_CreateClientAsync(ClientControllerExtensions.GetDefaultClient(1), Admin);
        await _clientSecretController.Call_CreateSecretAsync(new ClientPropertySecretDtoCreate
        {
            ClientId = createdClient.Id,
            Description = "Test Secret",
            ValidityPeriodYears = 2
        }, Admin);

        var api = await _apiResourceController.Call_CreateApiResourceAsync(ApiResourceControllerExtensions.GetDefaultApiResource(1), Admin);
        var apiScope = await _apiResourceScopeController.Call_AddApiResourceScopeAsync(
            ApiResourceScopeControllerExtensions.NewScopeFor(api.Id, Guid.NewGuid().ToString()), Admin);
        await _clientScopeController.Call_AddClientScopeAsync(createdClient.Id, apiScope.Scope, Admin);

        // Act
        var result = await _clientController.Call_DeleteClientAsync(createdClient.Id, Admin);

        // Assert - Verify deletion was successful
        Assert.That(result, Is.EqualTo(createdClient.Id));

        var response = await _clientController.GetClientByIdAsync(createdClient.Id);
        Assert.That(response.Result, Is.TypeOf<NotFoundResult>());
    }

    [Test]
    public async Task DeleteClientAsync_InvalidatesClientCache()
    {
        // Arrange
        var createdClient = await _clientController.Call_CreateClientAsync(ClientControllerExtensions.GetDefaultClient(1), Admin);

        // Act
        await _clientController.Call_DeleteClientAsync(createdClient.Id, Admin);

        // Assert
        await _clientCache.Received(1).RemoveAsync(createdClient.ClientId);
    }

    [TestCaseSource(nameof(UpdateClientRequesterCases))]
    public async Task UpdateClientAsync_ReturnsRequester(ClaimsPrincipal principal)
    {
        // Arrange
        var createdClient = await _clientController.Call_CreateClientAsync(ClientControllerExtensions.GetDefaultClient(1), Admin);
        var clientUpdate = new ClientDtoUpdate
        {
            Id = createdClient.Id,
            Description = "UpdatedDescription",
        };

        // Act
        var updatedResource = await _clientController.Call_UpdateClientAsync(clientUpdate, principal);

        // Assert
        Assert.That(updatedResource.AccessLevel, Is.EqualTo(SystemPermissionRoleType.Writer));
    }

    private static IEnumerable<TestCaseData> UpdateClientRequesterCases()
    {
        yield return new TestCaseData(Admin);
        yield return new TestCaseData(Contributor);
    }

    [Test]
    public async Task UpdateClientAsync_InvalidatesClientCache()
    {
        // Arrange
        var createdClient = await _clientController.Call_CreateClientAsync(ClientControllerExtensions.GetDefaultClient(1), Admin);
        var clientUpdate = new ClientDtoUpdate
        {
            Id = createdClient.Id,
            Description = "UpdatedDescription",
        };

        // Act
        await _clientController.Call_UpdateClientAsync(clientUpdate, Admin);

        // Assert
        await _clientCache.Received(1).RemoveAsync(createdClient.ClientId);
    }

    [TestCaseSource(nameof(GetByIdClientRequesterCases))]
    public async Task GetClientAsync_ReturnsRequester(ClaimsPrincipal principal)
    {
        // Arrange
        var createdClient = await _clientController.Call_CreateClientAsync(ClientControllerExtensions.GetDefaultClient(1), Admin);

        // Act
        var resource = await _clientController.Call_GetClientAsync(createdClient.Id, principal);

        // Assert
        Assert.That(resource.AccessLevel, Is.EqualTo(SystemPermissionRoleType.Writer));
    }

    [Test]
    public async Task GetClientAsync_ReturnsLastUpdatedTimestamp()
    {
        // Arrange
        var createdClient = await _clientController.Call_CreateClientAsync(ClientControllerExtensions.GetDefaultClient(1), Admin);
        var ts = DateTime.UtcNow;
        _clientAuditService.GetLastModifiedByIdAsync(createdClient.Id).Returns(new EntityLastModifiedData
        {
            Id = createdClient.Id,
            LastModified = ts,
            Reason = "Scope"
        });

        // Act
        var resource = await _clientController.Call_GetClientAsync(createdClient.Id, Admin);

        // Assert
        Assert.That(resource.Updated, Is.EqualTo(ts));
    }

    [Test]
    public async Task GetClientAsync_WithInvalidId_ReturnsNotFound()
    {
        // Arrange
        SetControllerContext(_clientController, Contributor);

        // Act
        var response = await _clientController.GetClientByIdAsync(9999);

        // Assert
        Assert.That(response.Result, Is.TypeOf<NotFoundResult>());
    }

    [Test]
    public async Task GetClientsPagedAsync_WithoutAuditData_ReturnsClientsWithOriginalUpdatedValue()
    {
        // Arrange
        var createdClient1 = await _clientController.Call_CreateClientAsync(ClientControllerExtensions.GetDefaultClient(1), Admin);
        var createdClient2 = await _clientController.Call_CreateClientAsync(ClientControllerExtensions.GetDefaultClient(1), Admin);
        var ts = DateTime.UtcNow;
        await _clientController.Call_UpdateClientAsync(new ClientDtoUpdate
        {
            Id = createdClient2.Id,
            Description = "Updated Description"
        }, Admin);

        // Act
        var clients = await _clientController.Call_GetClientsPagedAsync(Admin);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(clients, Has.Count.EqualTo(2));
            Assert.That(clients.First(c => c.Id == createdClient1.Id).Updated, Is.Null);
            Assert.That(clients.First(c => c.Id == createdClient2.Id).Updated, Is.GreaterThanOrEqualTo(ts).And.LessThanOrEqualTo(DateTime.UtcNow));
        }
    }

    [Test]
    public async Task GetClientsPagedAsync_WithAuditData_ReturnsClientsWithAuditTimestamps()
    {
        // Arrange
        var createdClient1 = await _clientController.Call_CreateClientAsync(ClientControllerExtensions.GetDefaultClient(1), Admin);
        var createdClient2 = await _clientController.Call_CreateClientAsync(ClientControllerExtensions.GetDefaultClient(1), Admin);
        
        var ts1 = DateTime.UtcNow.AddMinutes(-10);
        var ts2 = DateTime.UtcNow.AddMinutes(-5);
        
        var lastModifiedDict = new Dictionary<int, EntityLastModifiedData>
        {
            { createdClient1.Id, new EntityLastModifiedData { Id = createdClient1.Id, LastModified = ts1 } },
            { createdClient2.Id, new EntityLastModifiedData { Id = createdClient2.Id, LastModified = ts2 } }
        };

        _clientAuditService.GetLastModifiedByIdAsync(Arg.Any<List<int>>()).Returns(lastModifiedDict);

        // Act
        var clients = await _clientController.Call_GetClientsPagedAsync(Admin);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(clients, Has.Count.EqualTo(2));
            Assert.That(clients.FirstOrDefault(c => c.Id == createdClient1.Id)?.Updated, Is.EqualTo(ts1));
            Assert.That(clients.FirstOrDefault(c => c.Id == createdClient2.Id)?.Updated, Is.EqualTo(ts2));
        }
    }

    [Test]
    public async Task GetClientsByScopePagedAsync_WithMatchingScope_ReturnsClientsWithScope()
    {
        // Arrange
        var api = await _apiResourceController.Call_CreateApiResourceAsync(ApiResourceControllerExtensions.GetDefaultApiResource(1), Admin);
        var scopeDto = ApiResourceScopeControllerExtensions.NewScopeFor(api.Id, Guid.NewGuid().ToString());
        var createdScope = await _apiResourceScopeController.Call_AddApiResourceScopeAsync(scopeDto, Admin);

        var client1 = await _clientController.Call_CreateClientAsync(ClientControllerExtensions.GetDefaultClient(1), Admin);
        var client2 = await _clientController.Call_CreateClientAsync(ClientControllerExtensions.GetDefaultClient(1), Admin);
        var client3 = await _clientController.Call_CreateClientAsync(ClientControllerExtensions.GetDefaultClient(1), Admin);

        // Only add scope to client1 and client2
        await _clientScopeController.Call_AddClientScopeAsync(client1.Id, createdScope.Scope, Admin);
        await _clientScopeController.Call_AddClientScopeAsync(client2.Id, createdScope.Scope, Admin);

        // Act
        var clients = await _clientController.Call_GetClientsByScopePagedAsync(createdScope.Scope, Admin);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(clients, Has.Count.EqualTo(2));
            Assert.That(clients.Any(c => c.Id == client1.Id), Is.True);
            Assert.That(clients.Any(c => c.Id == client2.Id), Is.True);
            Assert.That(clients.Any(c => c.Id == client3.Id), Is.False);
        }
    }

    [Test]
    public async Task GetClientsByScopePagedAsync_WithNoMatchingClients_ReturnsEmptyList()
    {
        // Arrange
        var api = await _apiResourceController.Call_CreateApiResourceAsync(ApiResourceControllerExtensions.GetDefaultApiResource(1), Admin);
        var scopeDto = ApiResourceScopeControllerExtensions.NewScopeFor(api.Id, Guid.NewGuid().ToString());
        var createdScope = await _apiResourceScopeController.Call_AddApiResourceScopeAsync(scopeDto, Admin);

        // Create clients but don't assign the scope
        await _clientController.Call_CreateClientAsync(ClientControllerExtensions.GetDefaultClient(1), Admin);
        await _clientController.Call_CreateClientAsync(ClientControllerExtensions.GetDefaultClient(1), Admin);

        // Act
        var clients = await _clientController.Call_GetClientsByScopePagedAsync(createdScope.Scope, Admin);

        // Assert
        Assert.That(clients, Is.Empty);
    }

    [Test]
    public async Task GetClientsByScopePagedAsync_WithNonExistentScope_ReturnsEmptyList()
    {
        // Arrange
        await _clientController.Call_CreateClientAsync(ClientControllerExtensions.GetDefaultClient(1), Admin);

        // Act
        var clients = await _clientController.Call_GetClientsByScopePagedAsync("non-existent-scope", Admin);

        // Assert
        Assert.That(clients, Is.Empty);
    }

    [Test]
    public async Task GetClientsByScopePagedAsync_WithMultipleScopes_ReturnsOnlyClientsWithSpecificScope()
    {
        // Arrange
        var api = await _apiResourceController.Call_CreateApiResourceAsync(ApiResourceControllerExtensions.GetDefaultApiResource(1), Admin);
        var scopeDto1 = ApiResourceScopeControllerExtensions.NewScopeFor(api.Id, Guid.NewGuid().ToString());
        var scopeDto2 = ApiResourceScopeControllerExtensions.NewScopeFor(api.Id, Guid.NewGuid().ToString());
        var createdScope1 = await _apiResourceScopeController.Call_AddApiResourceScopeAsync(scopeDto1, Admin);
        var createdScope2 = await _apiResourceScopeController.Call_AddApiResourceScopeAsync(scopeDto2, Admin);

        var client1 = await _clientController.Call_CreateClientAsync(ClientControllerExtensions.GetDefaultClient(1), Admin);
        var client2 = await _clientController.Call_CreateClientAsync(ClientControllerExtensions.GetDefaultClient(1), Admin);
        var client3 = await _clientController.Call_CreateClientAsync(ClientControllerExtensions.GetDefaultClient(1), Admin);

        // client1 has scope1, client2 has scope2, client3 has both
        await _clientScopeController.Call_AddClientScopeAsync(client1.Id, createdScope1.Scope, Admin);
        await _clientScopeController.Call_AddClientScopeAsync(client2.Id, createdScope2.Scope, Admin);
        await _clientScopeController.Call_AddClientScopeAsync(client3.Id, createdScope1.Scope, Admin);
        await _clientScopeController.Call_AddClientScopeAsync(client3.Id, createdScope2.Scope, Admin);

        // Act
        var clientsWithScope1 = await _clientController.Call_GetClientsByScopePagedAsync(createdScope1.Scope, Admin);
        var clientsWithScope2 = await _clientController.Call_GetClientsByScopePagedAsync(createdScope2.Scope, Admin);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(clientsWithScope1, Has.Count.EqualTo(2));
            Assert.That(clientsWithScope1.Any(c => c.Id == client1.Id), Is.True);
            Assert.That(clientsWithScope1.Any(c => c.Id == client3.Id), Is.True);

            Assert.That(clientsWithScope2, Has.Count.EqualTo(2));
            Assert.That(clientsWithScope2.Any(c => c.Id == client2.Id), Is.True);
            Assert.That(clientsWithScope2.Any(c => c.Id == client3.Id), Is.True);
        }
    }

    private static IEnumerable<TestCaseData> GetByIdClientRequesterCases()
    {
        yield return new TestCaseData(Admin);
        yield return new TestCaseData(Contributor);
        yield return new TestCaseData(Reader);
        yield return new TestCaseData(SuperUser);
    }
}
