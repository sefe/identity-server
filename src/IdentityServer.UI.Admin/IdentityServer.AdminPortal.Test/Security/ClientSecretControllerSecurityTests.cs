// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

using Microsoft.Extensions.DependencyInjection;
using IdentityServer.Abstraction.DTO.Clients;
using IdentityServer.Abstraction.Entities.IdentityServerConfig.SystemPermissions;
using IdentityServer.Abstraction.Exceptions;
using IdentityServer.AdminPortal.Server.Controllers;
using IdentityServer.AdminPortal.Test.Controller;
using IdentityServer.AdminPortal.Test.Extensions;

namespace IdentityServer.AdminPortal.Test.Security;

public class ClientSecretControllerSecurityTests : ControllerTestBase
{
    private readonly SystemPermissionUtility _permissionUtil = new();
    private ClientPropertySecretController _clientSecretController;
    private ClientController _clientController;

    [SetUp]
    public void SetupAsync()
    {
        var provider = IoC.GetProvider(sc =>
        {
            _permissionUtil.AddToServiceCollection(sc);
            sc.AddScoped<ClientPropertySecretController>();
            sc.AddScoped<ClientController>();
        });

        _permissionUtil.Setup(provider);

        _clientSecretController = provider.GetRequiredService<ClientPropertySecretController>();
        _clientController = provider.GetRequiredService<ClientController>();

        SetControllerContext(_clientSecretController, Admin);
        SetControllerContext(_clientController, Admin);
    }

    [Test]
    public async Task Add_ClientSecret_AccessibleClient()
    {
        // Arrange
        // sp -> env -> client; User with Writer access
        var (permission, client) = await SetupTestDataAsync();
        _ = await _permissionUtil.AssignPermissionToUser(Contributor, permission, SystemPermissionEnvironmentNames.Development, SystemPermissionRoleType.Writer);

        var clientSecret = new ClientPropertySecretDtoCreate { ClientId = client.Id, Description = "secret1", ValidityPeriodYears = 2 };

        // Act
        var result = await _clientSecretController.Call_CreateSecretAsync(clientSecret, Contributor);

        // Assert
        Assert.That(result, Is.Not.Null);
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result.ClientId, Is.EqualTo(client.Id));
            Assert.That(result.Value, Is.Not.Null);
        }
    }

    [Test]
    public async Task Add_ClientSecret_ReadonlyClient()
    {
        // Arrange
        // sp -> env -> client; User with Reader access
        var (permission, client) = await SetupTestDataAsync();
        _ = await _permissionUtil.AssignPermissionToUser(Contributor, permission, SystemPermissionEnvironmentNames.Development, SystemPermissionRoleType.Reader);

        var clientSecret = new ClientPropertySecretDtoCreate { ClientId = client.Id, Description = "secret1", ValidityPeriodYears = 2 };

        // Act & Assert
        Assert.ThrowsAsync<EntityAccessException>(() => _clientSecretController.Call_CreateSecretAsync(clientSecret, Contributor));
    }

    [Test]
    public async Task Add_ClientSecret_InaccessibleClient()
    {
        // Arrange
        // sp -> env -> client; User with NO access
        var (permission, client) = await SetupTestDataAsync();

        var clientSecret = new ClientPropertySecretDtoCreate { ClientId = client.Id, Description = "secret1", ValidityPeriodYears = 2 };

        // Act & Assert
        Assert.ThrowsAsync<EntityAccessException>(() => _clientSecretController.Call_CreateSecretAsync(clientSecret, Contributor));
    }

    [Test]
    public async Task Delete_ClientSecret_AccessibleClient()
    {
        // Arrange
        // sp -> env -> client + secret; User with Writer access
        var (permission, client) = await SetupTestDataAsync();
        var clientSecret = new ClientPropertySecretDtoCreate { ClientId = client.Id, Description = "secret1", ValidityPeriodYears = 2 };
        var createdSecret = await _clientSecretController.Call_CreateSecretAsync(clientSecret, Admin);
        _ = await _permissionUtil.AssignPermissionToUser(Contributor, permission, SystemPermissionEnvironmentNames.Development, SystemPermissionRoleType.Writer);

        // Act
        var result = await _clientSecretController.Call_DeleteSecretAsync(createdSecret.Id, Contributor);

        // Assert
        Assert.That(result, Is.EqualTo(createdSecret.Id));
    }

    [Test]
    public async Task Delete_ClientSecret_ReadonlyClient()
    {
        // Arrange
        // sp -> env -> client + secret; User with Reader access
        var (permission, client) = await SetupTestDataAsync();
        var clientSecret = new ClientPropertySecretDtoCreate { ClientId = client.Id, Description = "secret1", ValidityPeriodYears = 2 };
        var createdSecret = await _clientSecretController.Call_CreateSecretAsync(clientSecret, Admin);
        _ = await _permissionUtil.AssignPermissionToUser(Contributor, permission, SystemPermissionEnvironmentNames.Development, SystemPermissionRoleType.Reader);

        // Act & Assert
        Assert.ThrowsAsync<EntityAccessException>(() => _clientSecretController.Call_DeleteSecretAsync(createdSecret.Id, Contributor));
    }

    [Test]
    public async Task Delete_ClientSecret_InaccessibleClient()
    {
        // Arrange
        // sp -> env -> client + secret; User with NO access
        var (permission, client) = await SetupTestDataAsync();
        var clientSecret = new ClientPropertySecretDtoCreate { ClientId = client.Id, Description = "secret1", ValidityPeriodYears = 2 };
        var createdSecret = await _clientSecretController.Call_CreateSecretAsync(clientSecret, Admin);

        // Act & Assert
        Assert.ThrowsAsync<EntityAccessException>(() => _clientSecretController.Call_DeleteSecretAsync(createdSecret.Id, Contributor));
    }

    private async Task<(SystemPermission permission, ClientDtoRead client)> SetupTestDataAsync()
    {
        var testPermission = await _permissionUtil.CreatePermission(Admin, SystemPermissionUtility.GetNewSystemPermission(), _permissionUtil.DefaultEnvironments);
        var res = await _clientController.Call_CreateClientAsync(ClientControllerExtensions.GetDefaultClient(testPermission.Environments.First().Id), Admin);
        return (testPermission, res);
    }
}
