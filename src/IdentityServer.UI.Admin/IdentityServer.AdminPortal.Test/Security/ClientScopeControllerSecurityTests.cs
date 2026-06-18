using Microsoft.Extensions.DependencyInjection;
using IdentityServer.Abstraction.Entities.IdentityServerConfig.SystemPermissions;
using IdentityServer.Abstraction.Exceptions;
using IdentityServer.AdminPortal.Server.Controllers;
using IdentityServer.AdminPortal.Test.Controller;
using IdentityServer.AdminPortal.Test.Extensions;
using IdentityServer.Tests.Common;

namespace IdentityServer.AdminPortal.Test.Security;

public class ClientControllerAdditionalSecurityTests : ControllerTestBase
{
    private readonly SystemPermissionUtility _permissionUtil = new();
    private ClientController _clientController;
    private ClientPropertyScopeController _clientScopeController;
    private ApiResourceController _apiResourceController;
    private ApiResourcePropertyScopeController _apiResourceScopeController;

    [SetUp]
    public void Setup()
    {
        var provider = IoC.GetProvider(sc =>
        {
            _permissionUtil.AddToServiceCollection(sc);
            sc.AddScoped<ClientController>();
            sc.AddScoped<ClientPropertyScopeController>();
            sc.AddScoped<ApiResourceController>();
            sc.AddScoped<ApiResourcePropertyScopeController>();
        });

        _permissionUtil.Setup(provider);

        _clientController = provider.GetRequiredService<ClientController>();
        _clientScopeController = provider.GetRequiredService<ClientPropertyScopeController>();
        _apiResourceController = provider.GetRequiredService<ApiResourceController>();
        _apiResourceScopeController = provider.GetRequiredService<ApiResourcePropertyScopeController>();
    }

    #region Create

    [Test]
    public async Task Create_Client_With_AccessibleScope()
    {
        // Arrange
        // User 1 - Writer of env1
        // permission 1 - env1 - client 1
        // permission 1 - env1 - api 1 (scope)
        var sp = await _permissionUtil.CreatePermission(SuperUser, SystemPermissionUtility.GetNewSystemPermission(), _permissionUtil.DefaultEnvironments);
        sp = await _permissionUtil.AssignPermissionToUser(Contributor, sp, SystemPermissionEnvironmentNames.Development, SystemPermissionRoleType.Writer);
        var api = await _apiResourceController.Call_CreateApiResourceAsync(ApiResourceControllerExtensions.GetDefaultApiResource(sp.Environments.First().Id), Admin);
        var scopeDto = ApiResourceScopeControllerExtensions.NewScopeFor(api.Id, Guid.NewGuid().ToString());
        _ = await _apiResourceScopeController.Call_AddApiResourceScopeAsync(scopeDto, Admin);

        var client = await _clientController.Call_CreateClientAsync(ClientControllerExtensions.GetDefaultClient(sp.Environments.First().Id), Contributor);

        // Act
        var addedScope = await _clientScopeController.Call_AddClientScopeAsync(client.Id, scopeDto.Name, Contributor);
        var updatedClient = await _clientController.Call_GetClientAsync(client.Id, Contributor);

        // Assert
        ClientScopeControllerExtensions.AssertClientScopeIsValid(addedScope, client.Id, scopeDto.Name);
        ClientScopeControllerExtensions.AssertClientScopeHasApiScope(addedScope, scopeDto);
        ClientScopeControllerExtensions.AssertClientHasScope(updatedClient, scopeDto.Name);
    }

    [TestCase(nameof(Admin))]
    [TestCase(nameof(Contributor))]
    public async Task Create_Client_NonExistentScope(string userName)
    {
        // Arrange
        // User - Writer of env1
        // permission 1 - env1 - client 1

        var user = TestUser.Get(userName);
        var sp = await _permissionUtil.CreatePermission(SuperUser, SystemPermissionUtility.GetNewSystemPermission(), _permissionUtil.StandardEnvironments);
        sp = await _permissionUtil.AssignPermissionToUser(user, sp, _permissionUtil.StandardEnvironments.First(), SystemPermissionRoleType.Writer);
        var scope = Guid.NewGuid().ToString();

        var client = await _clientController.Call_CreateClientAsync(ClientControllerExtensions.GetDefaultClient(sp.Environments.First().Id), user);

        // Act & Assert
        var exception = Assert.ThrowsAsync<EntityReferenceException>(() => _clientScopeController.Call_AddClientScopeAsync(client.Id, scope, user));
        Assert.That(exception!.Message, Does.Contain($"Scope '{scope}' doesn't exist."));
    }

    [Test]
    public async Task Create_Client_WithCrossEnvScope()
    {
        // Arrange
        // User - Writer of env1, Reader of env2
        // permission 1 - env1 - client 1
        // permission 1 - env2 - api 1 (scope)

        var sp = await _permissionUtil.CreatePermission(SuperUser, SystemPermissionUtility.GetNewSystemPermission(), _permissionUtil.StandardEnvironments);
        sp = await _permissionUtil.AssignPermissionToUser(Contributor, sp, _permissionUtil.StandardEnvironments.First(), SystemPermissionRoleType.Writer);
        var api = await _apiResourceController.Call_CreateApiResourceAsync(ApiResourceControllerExtensions.GetDefaultApiResource(sp.Environments.Last().Id), Admin);
        var scopeDto = ApiResourceScopeControllerExtensions.NewScopeFor(api.Id, Guid.NewGuid().ToString());
        _ = await _apiResourceScopeController.Call_AddApiResourceScopeAsync(scopeDto, Admin);

        var client = await _clientController.Call_CreateClientAsync(ClientControllerExtensions.GetDefaultClient(sp.Environments.First().Id), Contributor);

        // Act & Assert
        var exception = Assert.ThrowsAsync<EntityAccessException>(() => _clientScopeController.Call_AddClientScopeAsync(client.Id, scopeDto.Name, Contributor));
        using (Assert.EnterMultipleScope())
        {
            Assert.That(exception!.Message, Does.Contain(scopeDto.Name));
            Assert.That(exception!.Message, Does.Contain("Only scopes from client system permission environment"));
        }
    }

    [Test]
    public async Task Create_Client_InReadonlyEnvironment()
    {
        // Arrange
        // User - Reader of env1
        // permission 1 - env1 - client 1

        var sp = await _permissionUtil.CreatePermission(SuperUser, SystemPermissionUtility.GetNewSystemPermission(), _permissionUtil.StandardEnvironments);
        sp = await _permissionUtil.AssignPermissionToUser(Contributor, sp, _permissionUtil.StandardEnvironments.First(), SystemPermissionRoleType.Reader);
        var client = ClientControllerExtensions.GetDefaultClient(sp.Environments.First().Id);

        // Act & Assert
        var exception = Assert.ThrowsAsync<EntityAccessException>(() => _clientController.Call_CreateClientAsync(client, Contributor));
        Assert.That(exception!.Message, Does.Contain("Restricted system permission environment"));
    }

    #endregion

    #region Update

    [Test]
    public async Task Update_Client_InReadonlyEnvironment()
    {
        // Arrange
        // User 1 - Reader of env1
        // permission 1 - env1 - client 1
        // permission 1 - env1 - api 1 (scope)

        var sp = await _permissionUtil.CreatePermission(SuperUser, SystemPermissionUtility.GetNewSystemPermission(), _permissionUtil.DefaultEnvironments);
        sp = await _permissionUtil.AssignPermissionToUser(Contributor, sp, SystemPermissionEnvironmentNames.Development, SystemPermissionRoleType.Reader);
        var createdClient = await _clientController.Call_CreateClientAsync(ClientControllerExtensions.GetDefaultClient(sp.Environments.First().Id), Admin);
        var api = await _apiResourceController.Call_CreateApiResourceAsync(ApiResourceControllerExtensions.GetDefaultApiResource(sp.Environments.First().Id), Admin);
        var scopeDto = ApiResourceScopeControllerExtensions.NewScopeFor(api.Id, Guid.NewGuid().ToString());
        _ = await _apiResourceScopeController.Call_AddApiResourceScopeAsync(scopeDto, Admin);

        // Act & Assert
        var exception = Assert.ThrowsAsync<EntityAccessException>(() => _clientScopeController.Call_AddClientScopeAsync(createdClient.Id, scopeDto.Name, Contributor));
        Assert.That(exception!.Message, Does.Contain("Restricted system permission environment"));
    }

    [Test]
    public async Task Update_Client_Add_AccessibleScope()
    {
        // Arrange
        // User 1 - Writer of env1
        // permission 1 - env1 - client 1
        // permission 1 - env1 - api 1 (scope)

        var sp = await _permissionUtil.CreatePermission(SuperUser, SystemPermissionUtility.GetNewSystemPermission(), _permissionUtil.DefaultEnvironments);
        sp = await _permissionUtil.AssignPermissionToUser(Contributor, sp, SystemPermissionEnvironmentNames.Development, SystemPermissionRoleType.Writer);
        var createdClient = await _clientController.Call_CreateClientAsync(ClientControllerExtensions.GetDefaultClient(sp.Environments.First().Id), Admin);
        var api = await _apiResourceController.Call_CreateApiResourceAsync(ApiResourceControllerExtensions.GetDefaultApiResource(sp.Environments.First().Id), Admin);
        var scopeDto = ApiResourceScopeControllerExtensions.NewScopeFor(api.Id, Guid.NewGuid().ToString());
        _ = await _apiResourceScopeController.Call_AddApiResourceScopeAsync(scopeDto, Admin);

        // Act
        var addedScope = await _clientScopeController.Call_AddClientScopeAsync(createdClient.Id, scopeDto.Name, Contributor);
        var updatedClient = await _clientController.Call_GetClientAsync(createdClient.Id, Contributor);

        // Assert
        ClientScopeControllerExtensions.AssertClientScopeIsValid(addedScope, createdClient.Id, scopeDto.Name);
        ClientScopeControllerExtensions.AssertClientScopeHasApiScope(addedScope, scopeDto);
        ClientScopeControllerExtensions.AssertClientHasScope(updatedClient, scopeDto.Name);
    }

    [TestCase(nameof(Admin))]
    [TestCase(nameof(Contributor))]
    public async Task Update_Client_NonExistentScope(string userName)
    {
        // Arrange
        // User - Writer of env1
        // permission 1 - env1 - client 1

        var user = TestUser.Get(userName);
        var sp = await _permissionUtil.CreatePermission(SuperUser, SystemPermissionUtility.GetNewSystemPermission(), _permissionUtil.StandardEnvironments);
        sp = await _permissionUtil.AssignPermissionToUser(user, sp, _permissionUtil.StandardEnvironments.First(), SystemPermissionRoleType.Writer);
        var createdClient = await _clientController.Call_CreateClientAsync(ClientControllerExtensions.GetDefaultClient(sp.Environments.First().Id), Admin);

        var scope = Guid.NewGuid().ToString();

        // Act & Assert
        var exception = Assert.ThrowsAsync<EntityReferenceException>(() => _clientScopeController.Call_AddClientScopeAsync(createdClient.Id, scope, user));
        Assert.That(exception!.Message, Does.Contain($"Scope '{scope}' doesn't exist."));
    }

    /// <summary>
    /// If User modifies a client with existing scope that User doesn't have Write access to,
    /// the operation should still succeed given that User has Write access to the Environment
    /// </summary>
    /// <returns></returns>
    [Test]
    public async Task Update_Client_WithInaccessibleScope_Add_AccessibleScope()
    {
        // Arrange
        // User 1 - Writer of env1, Reader of env2
        // permission 1 - env1 - client 1
        // permission 1 - env1 - api 1 (scopeByUser)
        // permission 1 - env2 - api 2 (scopeByAdmin)

        var sp = await _permissionUtil.CreatePermission(SuperUser, SystemPermissionUtility.GetNewSystemPermission(), _permissionUtil.DefaultEnvironments);
        sp = await _permissionUtil.AssignPermissionToUser(Contributor, sp, sp.Environments.First().Environment, SystemPermissionRoleType.Writer);
        var client = ClientControllerExtensions.GetDefaultClient(sp.Environments.First().Id);
        var api1 = await _apiResourceController.Call_CreateApiResourceAsync(ApiResourceControllerExtensions.GetDefaultApiResource(sp.Environments.Last().Id), Admin);
        var scopeDtoByAdmin = ApiResourceScopeControllerExtensions.NewScopeFor(api1.Id, Guid.NewGuid().ToString());
        _ = await _apiResourceScopeController.Call_AddApiResourceScopeAsync(scopeDtoByAdmin, Admin);

        var createdClient = await _clientController.Call_CreateClientAsync(client, Admin);
        _ = await _clientScopeController.Call_AddClientScopeAsync(createdClient.Id, scopeDtoByAdmin.Name, Admin);

        var api2 = await _apiResourceController.Call_CreateApiResourceAsync(ApiResourceControllerExtensions.GetDefaultApiResource(sp.Environments.First().Id), Admin);
        var scopeDtoByUser = ApiResourceScopeControllerExtensions.NewScopeFor(api2.Id, Guid.NewGuid().ToString());
        _ = await _apiResourceScopeController.Call_AddApiResourceScopeAsync(scopeDtoByUser, Admin);

        // Act
        var addedScope = await _clientScopeController.Call_AddClientScopeAsync(createdClient.Id, scopeDtoByUser.Name, Contributor);
        var updatedClient = await _clientController.Call_GetClientAsync(createdClient.Id, Contributor);

        // Assert
        ClientScopeControllerExtensions.AssertClientScopeIsValid(addedScope, createdClient.Id, scopeDtoByUser.Name);
        ClientScopeControllerExtensions.AssertClientScopeHasApiScope(addedScope, scopeDtoByUser);
        ClientScopeControllerExtensions.AssertClientHasScope(updatedClient, scopeDtoByAdmin.Name, scopeDtoByUser.Name);
    }

    [Test]
    public async Task Update_Client_AddCrossEnvScope()
    {
        // Arrange
        // User - Writer of env1, Reader of env2
        // permission 1 - env1 - client 1
        // permission 1 - env2 - api 1 (scope)

        var sp = await _permissionUtil.CreatePermission(SuperUser, SystemPermissionUtility.GetNewSystemPermission(), _permissionUtil.StandardEnvironments);
        sp = await _permissionUtil.AssignPermissionToUser(Contributor, sp, _permissionUtil.StandardEnvironments.First(), SystemPermissionRoleType.Writer);
        sp = await _permissionUtil.AssignPermissionToUser(Contributor, sp, _permissionUtil.StandardEnvironments.Last(), SystemPermissionRoleType.Reader);
        var createdClient = await _clientController.Call_CreateClientAsync(ClientControllerExtensions.GetDefaultClient(sp.Environments.First().Id), Admin);
        var api = await _apiResourceController.Call_CreateApiResourceAsync(ApiResourceControllerExtensions.GetDefaultApiResource(sp.Environments.Last().Id), Admin);
        var scopeDto = ApiResourceScopeControllerExtensions.NewScopeFor(api.Id, Guid.NewGuid().ToString());
        _ = await _apiResourceScopeController.Call_AddApiResourceScopeAsync(scopeDto, Admin);

        // Act & Assert
        var exception = Assert.ThrowsAsync<EntityAccessException>(() => _clientScopeController.Call_AddClientScopeAsync(createdClient.Id, scopeDto.Name, Contributor));
        using (Assert.EnterMultipleScope())
        {
            Assert.That(exception!.Message, Does.Contain(scopeDto.Name));
            Assert.That(exception!.Message, Does.Contain("Only scopes from client system permission environment"));
        }
    }

    #endregion
}
