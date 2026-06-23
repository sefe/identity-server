// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

using Microsoft.Extensions.DependencyInjection;
using IdentityServer.Abstraction.DTO.Clients;
using IdentityServer.Abstraction.Entities.IdentityServerConfig.SystemPermissions;
using IdentityServer.Abstraction.Exceptions;
using IdentityServer.AdminPortal.Server.Controllers;
using IdentityServer.AdminPortal.Test.Extensions;
using IdentityServer.Tests.Common;

namespace IdentityServer.AdminPortal.Test.Controller;

public class ClientControllerCloningsTests : ControllerTestBase
{
    private ClientController _clientController;
    private ClientPropertyCorsController _clientCorsController;
    private ClientPropertyRedirectController _clientRedirectController;
    private ClientPropertyPostLogoutRedirectController _clientPostLogoutRedirectController;
    private ClientPropertyScopeController _clientScopeController;
    private ClientPropertyRoleController _clientRoleController;
    private ClientPropertySecretController _clientSecretController;
    private ApiResourceController _apiResourceController;
    private ApiResourcePropertyScopeController _apiResourceScopeController;

    [SetUp]
    public async Task Setup()
    {
        var provider = IoC.GetProvider(sc =>
        {
            sc.AddScoped<ClientController>();
            sc.AddScoped<ClientPropertyCorsController>();
            sc.AddScoped<ClientPropertyRedirectController>();
            sc.AddScoped<ClientPropertyPostLogoutRedirectController>();
            sc.AddScoped<ClientPropertyScopeController>();
            sc.AddScoped<ClientPropertySecretController>();
            sc.AddScoped<ClientPropertyRoleController>();
            sc.AddScoped<ApiResourceController>();
            sc.AddScoped<ApiResourcePropertyScopeController>();
            sc.ReplaceWithInstance(EverythingIsAllowed);
        });

        await Setup(provider);

        _clientController = provider.GetRequiredService<ClientController>();
        _clientCorsController = provider.GetRequiredService<ClientPropertyCorsController>();
        _clientRedirectController = provider.GetRequiredService<ClientPropertyRedirectController>();
        _clientPostLogoutRedirectController = provider.GetRequiredService<ClientPropertyPostLogoutRedirectController>();
        _clientScopeController = provider.GetRequiredService<ClientPropertyScopeController>();
        _clientSecretController = provider.GetRequiredService<ClientPropertySecretController>();
        _clientRoleController = provider.GetRequiredService<ClientPropertyRoleController>();
        _apiResourceController = provider.GetRequiredService<ApiResourceController>();
        _apiResourceScopeController = provider.GetRequiredService<ApiResourcePropertyScopeController>();
    }

    [Test]
    public async Task CloneClient_ClonesTopLevelProperties()
    {
        // Arrange
        var originalClient = await _clientController.Call_CreateClientAsync(
            ClientControllerExtensions.GetDefaultClient(1), Admin);

        var cloneRequest = new ClientDtoClone
        {
            Id = originalClient.Id,
            ClientId = "cloned-client-id",
            ClientName = "Cloned Client",
            SystemPermissionEnvironmentId = originalClient.SystemPermissionEnvironmentId
        };

        // Act
        var clonedClient = await _clientController.Call_CloneClientAsync(cloneRequest, Admin);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(clonedClient.Id, Is.Not.EqualTo(originalClient.Id));
            Assert.That(clonedClient.ClientId, Is.EqualTo(cloneRequest.ClientId));
            Assert.That(clonedClient.ClientName, Is.EqualTo(cloneRequest.ClientName));
            Assert.That(clonedClient.SystemPermissionEnvironmentId, Is.EqualTo(originalClient.SystemPermissionEnvironmentId));
            Assert.That(clonedClient.AccessLevel, Is.EqualTo(SystemPermissionRoleType.Writer));
            Assert.That(clonedClient.AllowedGrantTypes.Select(_ => _.GrantType), Is.EquivalentTo(originalClient.AllowedGrantTypes.Select(_ => _.GrantType)));
        }
    }

    [Test]
    public async Task CloneClient_ClonesRoles()
    {
        // Arrange
        var originalClient = await _clientController.Call_CreateClientAsync(ClientControllerExtensions.GetDefaultClient(1), Admin);
        var role1 = await _clientRoleController.Call_AddClientRoleAsync(originalClient.Id, "role1", Admin);
        var role2 = await _clientRoleController.Call_AddClientRoleAsync(originalClient.Id, "role2", Admin);
        var cloneRequest = new ClientDtoClone
        {
            Id = originalClient.Id,
            ClientId = "cloned-client-id",
            ClientName = "Cloned Client",
            SystemPermissionEnvironmentId = originalClient.SystemPermissionEnvironmentId
        };

        // Act
        var clonedClient = await _clientController.Call_CloneClientAsync(cloneRequest, Admin);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(clonedClient.Roles, Has.Count.EqualTo(2));
            Assert.That(clonedClient.Roles[0].RoleName, Is.EqualTo(role1.RoleName));
            Assert.That(clonedClient.Roles[1].RoleName, Is.EqualTo(role2.RoleName));

            // Verify mappings are not cloned
            Assert.That(clonedClient.Roles[0].Mappings, Is.Null.Or.Empty, "Role mappings should not be cloned.");
            Assert.That(clonedClient.Roles[1].Mappings, Is.Null.Or.Empty, "Role mappings should not be cloned.");
        }
    }

    [Test]
    public void CloneClient_WithInvalidId_Fails()
    {
        // Arrange
        var cloneRequest = new ClientDtoClone
        {
            Id = -1, // Invalid ID
            ClientId = "client-id",
            ClientName = "Invalid Clone Client",
            SystemPermissionEnvironmentId = 1
        };

        // Act & Assert
        Assert.ThrowsAsync<EntityNotFoundException>(() => _clientController.Call_CloneClientAsync(cloneRequest, Admin));
    }

    [Test]
    public void CloneClient_WithExistingClientId_Fails()
    {
        // Arrange
        var originalClient = _clientController.Call_CreateClientAsync(
            ClientControllerExtensions.GetDefaultClient(1), Admin).Result;

        var cloneRequest = new ClientDtoClone
        {
            Id = originalClient.Id,
            ClientId = originalClient.ClientId, // Duplicate ClientId
            ClientName = "Duplicate Client",
            SystemPermissionEnvironmentId = originalClient.SystemPermissionEnvironmentId
        };

        // Act & Assert
        Assert.ThrowsAsync<EntityAlreadyExistsException>(() => _clientController.Call_CloneClientAsync(cloneRequest, Admin));
    }

    [Test]
    public async Task CloneClient_RemovesCorsOrigins()
    {
        // Arrange
        var originalClient = _clientController.Call_CreateClientAsync(
            ClientControllerExtensions.GetDefaultClient(1), Admin).Result;

        _ = await _clientCorsController.Call_AddClientCorsAsync(originalClient.Id, "http://example.com", Admin);

        var cloneRequest = new ClientDtoClone
        {
            Id = originalClient.Id,
            ClientId = "cloned-client-id",
            ClientName = "Cloned Client",
            SystemPermissionEnvironmentId = 1
        };

        // Act
        var clonedClient = await _clientController.Call_CloneClientAsync(cloneRequest, Admin);

        // Assert
        Assert.That(clonedClient.AllowedCorsOrigins, Is.Null.Or.Empty, "AllowedCorsOrigins should be null in the cloned client.");
    }

    [Test]
    public async Task CloneClient_FiltersRedirectUris()
    {
        // Arrange
        var originalClient = _clientController.Call_CreateClientAsync(
            ClientControllerExtensions.GetDefaultClient(1), Admin).Result;

        _ = await _clientRedirectController.Call_AddClientRedirectAsync(originalClient.Id, "http://localhost/callback", Admin);
        _ = await _clientRedirectController.Call_AddClientRedirectAsync(originalClient.Id, "http://localhost:3200/callback", Admin);
        _ = await _clientRedirectController.Call_AddClientRedirectAsync(originalClient.Id, "https://example.com/callback", Admin);
        _ = await _clientRedirectController.Call_AddClientRedirectAsync(originalClient.Id, "https://example.com:3200/callback", Admin);
        _ = await _clientRedirectController.Call_AddClientRedirectAsync(originalClient.Id, "http://127.0.0.1/callback", Admin);
        _ = await _clientRedirectController.Call_AddClientRedirectAsync(originalClient.Id, "http://127.0.0.1:8000/callback", Admin);
        _ = await _clientRedirectController.Call_AddClientRedirectAsync(originalClient.Id, "aaa://test", Admin);

        var cloneRequest = new ClientDtoClone
        {
            Id = originalClient.Id,
            ClientId = "cloned-client-id",
            ClientName = "Cloned Client",
            SystemPermissionEnvironmentId = 1
        };

        // Act
        var clonedClient = await _clientController.Call_CloneClientAsync(cloneRequest, Admin);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(clonedClient.RedirectUris, Has.Count.EqualTo(4), "Only localhost URIs should be retained.");
            Assert.That(clonedClient.RedirectUris.Select(r => r.RedirectUri), Has.None.StartsWith("http://example"), "Only localhost URIs should be retained.");
            Assert.That(clonedClient.RedirectUris.Select(r => r.RedirectUri), Has.None.StartsWith("aaa://"), "Only localhost URIs should be retained.");
        }
    }

    [Test]
    public async Task CloneClient_FiltersPostLogoutRedirectUris()
    {
        // Arrange
        var originalClient = _clientController.Call_CreateClientAsync(
            ClientControllerExtensions.GetDefaultClient(1), Admin).Result;

        _ = await _clientPostLogoutRedirectController.Call_AddClientPostLogoutRedirectAsync(originalClient.Id, "http://localhost/signout", Admin);
        _ = await _clientPostLogoutRedirectController.Call_AddClientPostLogoutRedirectAsync(originalClient.Id, "http://localhost:3200/signout", Admin);
        _ = await _clientPostLogoutRedirectController.Call_AddClientPostLogoutRedirectAsync(originalClient.Id, "https://example.com/signout", Admin);
        _ = await _clientPostLogoutRedirectController.Call_AddClientPostLogoutRedirectAsync(originalClient.Id, "https://example.com:3200/signout", Admin);
        _ = await _clientPostLogoutRedirectController.Call_AddClientPostLogoutRedirectAsync(originalClient.Id, "http://127.0.0.1/signout", Admin);
        _ = await _clientPostLogoutRedirectController.Call_AddClientPostLogoutRedirectAsync(originalClient.Id, "http://127.0.0.1:8000/signout", Admin);
        _ = await _clientPostLogoutRedirectController.Call_AddClientPostLogoutRedirectAsync(originalClient.Id, "aaa://test", Admin);

        var cloneRequest = new ClientDtoClone
        {
            Id = originalClient.Id,
            ClientId = "cloned-client-id",
            ClientName = "Cloned Client",
            SystemPermissionEnvironmentId = 1
        };

        // Act
        var clonedClient = await _clientController.Call_CloneClientAsync(cloneRequest, Admin);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(clonedClient.PostLogoutRedirectUris, Has.Count.EqualTo(4), "Only localhost URIs should be retained.");
            Assert.That(clonedClient.PostLogoutRedirectUris.Select(r => r.PostLogoutRedirectUri), Has.None.StartsWith("http://example"), "Only localhost URIs should be retained.");
            Assert.That(clonedClient.PostLogoutRedirectUris.Select(r => r.PostLogoutRedirectUri), Has.None.StartsWith("aaa://"), "Only localhost URIs should be retained.");
        }
    }

    [Test]
    public async Task CloneClient_FiltersAllowedScopes()
    {
        // Arrange
        var api = await _apiResourceController.Call_CreateApiResourceAsync(ApiResourceControllerExtensions.GetDefaultApiResource(1), Admin);
        _ = await _apiResourceScopeController.Call_AddApiResourceScopeAsync(ApiResourceScopeControllerExtensions.NewScopeFor(api.Id, "api1"), Admin);
        _ = await _apiResourceScopeController.Call_AddApiResourceScopeAsync(ApiResourceScopeControllerExtensions.NewScopeFor(api.Id, "api2"), Admin);

        var originalClient = await _clientController.Call_CreateClientAsync(
            ClientControllerExtensions.GetDefaultClient(1), Admin);
        _ = await _clientScopeController.Call_AddClientScopeAsync(originalClient.Id, "openid", Admin);
        _ = await _clientScopeController.Call_AddClientScopeAsync(originalClient.Id, $"{api.Name}.api1", Admin);
        _ = await _clientScopeController.Call_AddClientScopeAsync(originalClient.Id, $"{api.Name}.api2", Admin);

        var cloneRequest = new ClientDtoClone
        {
            Id = originalClient.Id,
            ClientId = "cloned-client-id",
            ClientName = "Cloned Client",
            SystemPermissionEnvironmentId = 1
        };

        // Act
        var clonedClient = await _clientController.Call_CloneClientAsync(cloneRequest, Admin);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(clonedClient.AllowedScopes, Has.Count.EqualTo(1), "Only OIDC standard scopes should be retained.");
            Assert.That(clonedClient.AllowedScopes[0].Scope, Is.EqualTo("openid"), "Only OIDC standard scopes should be retained.");
        }
    }

    [Test]
    public async Task CloneClient_RemovesClientSecrets()
    {
        // Arrange
        var originalClient = await _clientController.Call_CreateClientAsync(
            ClientControllerExtensions.GetDefaultClient(1), Admin);

        _ = _clientSecretController.Call_CreateSecretAsync(new() { ClientId = originalClient.Id, Description = "test secret desc" }, Admin);

        var cloneRequest = new ClientDtoClone
        {
            Id = originalClient.Id,
            ClientId = "cloned-client-id",
            ClientName = "Cloned Client",
            SystemPermissionEnvironmentId = 1
        };

        // Act
        var clonedClient = await _clientController.Call_CloneClientAsync(cloneRequest, Admin);

        // Assert
        Assert.That(clonedClient.ClientSecrets, Is.Null.Or.Empty, "ClientSecrets should be null in the cloned client.");
    }

    [Test]
    public async Task CloneClient_CopiesMultipleOidcScopes()
    {
        // Arrange
        var originalClient = await _clientController.Call_CreateClientAsync(
            ClientControllerExtensions.GetDefaultClient(1), Admin);

        _ = await _clientScopeController.Call_AddClientScopeAsync(originalClient.Id, "openid", Admin);
        _ = await _clientScopeController.Call_AddClientScopeAsync(originalClient.Id, "profile", Admin);
        _ = await _clientScopeController.Call_AddClientScopeAsync(originalClient.Id, "email", Admin);

        var cloneRequest = new ClientDtoClone
        {
            Id = originalClient.Id,
            ClientId = "cloned-client-id",
            ClientName = "Cloned Client",
            SystemPermissionEnvironmentId = 1
        };

        // Act
        var clonedClient = await _clientController.Call_CloneClientAsync(cloneRequest, Admin);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(clonedClient.AllowedScopes, Has.Count.EqualTo(3));
            Assert.That(clonedClient.AllowedScopes.Select(s => s.Scope), Does.Contain("openid"));
            Assert.That(clonedClient.AllowedScopes.Select(s => s.Scope), Does.Contain("profile"));
            Assert.That(clonedClient.AllowedScopes.Select(s => s.Scope), Does.Contain("email"));
        }
    }

    [Test]
    public async Task CloneClient_CopiesAllBasicProperties()
    {
        // Arrange
        var originalClient = await _clientController.Call_CreateClientAsync(
            ClientControllerExtensions.GetDefaultClient(1), Admin);

        var cloneRequest = new ClientDtoClone
        {
            Id = originalClient.Id,
            ClientId = "cloned-client-id",
            ClientName = "Cloned Client Name",
            SystemPermissionEnvironmentId = originalClient.SystemPermissionEnvironmentId
        };

        // Act
        var clonedClient = await _clientController.Call_CloneClientAsync(cloneRequest, Admin);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(clonedClient.Description, Is.EqualTo(originalClient.Description));
            Assert.That(clonedClient.Enabled, Is.EqualTo(originalClient.Enabled));
            Assert.That(clonedClient.RequireClientSecret, Is.EqualTo(originalClient.RequireClientSecret));
            Assert.That(clonedClient.RequirePkce, Is.EqualTo(originalClient.RequirePkce));
            Assert.That(clonedClient.AllowOfflineAccess, Is.EqualTo(originalClient.AllowOfflineAccess));
            Assert.That(clonedClient.AccessTokenType, Is.EqualTo(originalClient.AccessTokenType));
        }
    }

    [Test]
    public async Task CloneClient_WithNoOptionalProperties_Succeeds()
    {
        // Arrange
        var originalClient = await _clientController.Call_CreateClientAsync(
            ClientControllerExtensions.GetDefaultClient(1), Admin);

        // Ensure no optional properties are added
        var cloneRequest = new ClientDtoClone
        {
            Id = originalClient.Id,
            ClientId = "minimal-clone",
            ClientName = "Minimal Clone",
            SystemPermissionEnvironmentId = 1
        };

        // Act
        var clonedClient = await _clientController.Call_CloneClientAsync(cloneRequest, Admin);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(clonedClient.AllowedCorsOrigins, Is.Null.Or.Empty);
            Assert.That(clonedClient.ClientSecrets, Is.Null.Or.Empty);
            Assert.That(clonedClient.EntraApps, Is.Null.Or.Empty);
        }
    }
}
