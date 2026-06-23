// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

using AutoMapper;
using NSubstitute;
using System.Security.Claims;
using IdentityServer.Abstraction.Contracts;
using IdentityServer.Abstraction.DTO.Clients;
using IdentityServer.Abstraction.Entities.IdentityServerConfig;
using IdentityServer.Abstraction.Entities.IdentityServerConfig.SystemPermissions;
using IdentityServer.Abstraction.Exceptions;
using IdentityServer.Data.DuendeEntityExtensions;
using IdentityServer.Data.Entities.Roles;
using IdentityServer.Data.Repositories.DtoRepositories.Client;
using IdentityServer.Tests.Common;
using IdentityServer.Tests.Common.Builders;

namespace IdentityServer.Data.Test.Repositories;

[TestFixture]
public class ClientDtoCloneRepositoryTests
{
    private IStorage<ClientExt> _clientStorage;
    private IStorage<SystemPermissionEnvironment> _sysEnvStorage;
    private IMapper _mapper;
    private IPermissionChecker _permissionChecker;
    private ClientDtoCloneRepository _sut;
    private ClaimsPrincipal _user;

    [SetUp]
    public void SetUp()
    {
        _clientStorage = Substitute.For<IStorage<ClientExt>>();
        _sysEnvStorage = Substitute.For<IStorage<SystemPermissionEnvironment>>();
        _mapper = Substitute.For<IMapper>();
        _permissionChecker = Substitute.For<IPermissionChecker>();

        _sut = new ClientDtoCloneRepository(
            _clientStorage,
            _sysEnvStorage,
            _mapper,
            _permissionChecker);

        _user = TestUser.Admin;
    }

    [Test]
    public async Task CloneAsync_WithValidRequest_ClonesClientSuccessfully()
    {
        // Arrange
        var sourceClientId = 1;
        var sourceClient = new ClientExtBuilder("source-client", "Source Client")
            .WithId(sourceClientId)
            .Build();

        var targetEnvId = 2;
        var targetEnv = new SystemPermissionEnvironment
        {
            Id = targetEnvId,
            Environment = SystemPermissionEnvironmentNames.QA,
            SystemPermission = new SystemPermission
            {
                Name = "Test System Permission",
                Description = "Test environment"
            }
        };

        var cloneRequest = new ClientDtoClone
        {
            Id = sourceClientId,
            ClientId = "cloned-client",
            ClientName = "Cloned Client",
            SystemPermissionEnvironmentId = targetEnvId
        };

        _clientStorage.GetByIdAsync(sourceClientId).Returns(sourceClient);
        _clientStorage.FirstOrDefaultAsync(Arg.Any<System.Linq.Expressions.Expression<Func<ClientExt, bool>>>()).Returns((ClientExt)null);
        _sysEnvStorage.GetByIdAsync(targetEnvId).Returns(targetEnv);
        _permissionChecker.GetAccessRoleOrThrowIfNoAccessToEnvAsync(_user, targetEnvId, EntityAccessType.Create, "Application")
            .Returns(SystemPermissionRoleType.Writer);
        _permissionChecker.GetAccessRoleOrThrowIfNoAccessToEnvAsync(_user, sourceClient.SystemPermissionEnvironmentId, EntityAccessType.Read, Arg.Any<string>())
            .Returns(SystemPermissionRoleType.Reader);

        var clonedClient = new ClientExtBuilder("cloned-client", "Cloned Client")
            .WithId(999)
            .Build();
        _clientStorage.AddAsync(Arg.Any<ClientExt>()).Returns(clonedClient);

        var expectedDto = new ClientDtoRead
        {
            Id = 999,
            ClientId = "cloned-client",
            ClientName = "Cloned Client",
            SystemPermissionEnvironmentId = targetEnvId
        };
        _mapper.Map<ClientDtoRead>(Arg.Any<ClientExt>()).Returns(expectedDto);

        // Act
        var result = await _sut.CloneAsync(_user, cloneRequest);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result, Is.Not.Null);
            Assert.That(result.AccessLevel, Is.EqualTo(SystemPermissionRoleType.Writer));
            Assert.That(result.ClientId, Is.EqualTo(cloneRequest.ClientId));
            Assert.That(result.ClientName, Is.EqualTo(cloneRequest.ClientName));
        }
        await _clientStorage.Received(1).AddAsync(Arg.Is<ClientExt>(c =>
           c.ClientId == cloneRequest.ClientId &&
                c.ClientName == cloneRequest.ClientName &&
             c.SystemPermissionEnvironmentId == targetEnvId));
    }

    [Test]
    public void CloneAsync_WithNonExistentSourceClient_ThrowsEntityNotFoundException()
    {
        // Arrange
        var cloneRequest = new ClientDtoClone
        {
            Id = 999,
            ClientId = "cloned-client",
            ClientName = "Cloned Client",
            SystemPermissionEnvironmentId = 1
        };

        _clientStorage.GetByIdAsync(999).Returns((ClientExt)null);

        // Act & Assert
        var ex = Assert.ThrowsAsync<EntityNotFoundException>(() => _sut.CloneAsync(_user, cloneRequest));
        Assert.That(ex!.Message, Does.Contain("Application with Id 999 was not found"));
    }

    [Test]
    public void CloneAsync_WithExistingClientId_ThrowsEntityAlreadyExistsException()
    {
        // Arrange
        var sourceClient = new ClientExtBuilder("source-client", "Source Client")
            .WithId(1)
            .Build();

        var existingClient = new ClientExtBuilder("cloned-client", "Existing Client")
            .WithId(2)
            .Build();

        var cloneRequest = new ClientDtoClone
        {
            Id = 1,
            ClientId = "cloned-client",
            ClientName = "Cloned Client",
            SystemPermissionEnvironmentId = 1
        };

        _clientStorage.GetByIdAsync(1).Returns(sourceClient);
        _clientStorage.FirstOrDefaultAsync(Arg.Any<System.Linq.Expressions.Expression<Func<ClientExt, bool>>>()).Returns(existingClient);
        _permissionChecker.GetAccessRoleOrThrowIfNoAccessToEnvAsync(_user, 1, EntityAccessType.Create, "Application")
            .Returns(SystemPermissionRoleType.Writer);
        _permissionChecker.GetAccessRoleOrThrowIfNoAccessToEnvAsync(_user, sourceClient.SystemPermissionEnvironmentId, EntityAccessType.Read, Arg.Any<string>())
            .Returns(SystemPermissionRoleType.Reader);

        // Act & Assert
        var ex = Assert.ThrowsAsync<EntityAlreadyExistsException>(() => _sut.CloneAsync(_user, cloneRequest));
        Assert.That(ex!.Message, Does.Contain("Application with id 'cloned-client' already exists"));
    }

    [Test]
    public void CloneAsync_WithNonExistentTargetEnvironment_ThrowsEntityNotFoundException()
    {
        // Arrange
        var sourceClient = new ClientExtBuilder("source-client", "Source Client")
            .WithId(1)
            .Build();

        var cloneRequest = new ClientDtoClone
        {
            Id = 1,
            ClientId = "cloned-client",
            ClientName = "Cloned Client",
            SystemPermissionEnvironmentId = 999
        };

        _clientStorage.GetByIdAsync(1).Returns(sourceClient);
        _clientStorage.FirstOrDefaultAsync(Arg.Any<System.Linq.Expressions.Expression<Func<ClientExt, bool>>>()).Returns((ClientExt)null);
        _sysEnvStorage.GetByIdAsync(999).Returns((SystemPermissionEnvironment)null);
        _permissionChecker.GetAccessRoleOrThrowIfNoAccessToEnvAsync(_user, 999, EntityAccessType.Create, "Application")
            .Returns(SystemPermissionRoleType.Writer);
        _permissionChecker.GetAccessRoleOrThrowIfNoAccessToEnvAsync(_user, sourceClient.SystemPermissionEnvironmentId, EntityAccessType.Read, Arg.Any<string>())
            .Returns(SystemPermissionRoleType.Reader);

        // Act & Assert
        var ex = Assert.ThrowsAsync<EntityNotFoundException>(() => _sut.CloneAsync(_user, cloneRequest));
        Assert.That(ex!.Message, Does.Contain("System Permission Environment with Id 999 was not found"));
    }

    [Test]
    public void CloneAsync_WithNoCreatePermissionOnTargetEnv_ThrowsPermissionException()
    {
        // Arrange
        var cloneRequest = new ClientDtoClone
        {
            Id = 1,
            ClientId = "cloned-client",
            ClientName = "Cloned Client",
            SystemPermissionEnvironmentId = 2
        };

        _permissionChecker.GetAccessRoleOrThrowIfNoAccessToEnvAsync(_user, 2, EntityAccessType.Create, "Application")
            .Returns<SystemPermissionRoleType>(x => throw new EntityAccessException(_user, "Application", EntityAccessType.Create));

        // Act & Assert
        Assert.ThrowsAsync<EntityAccessException>(() => _sut.CloneAsync(_user, cloneRequest));
    }

    [Test]
    public void CloneAsync_WithNoReadPermissionOnSourceEnv_ThrowsPermissionException()
    {
        // Arrange
        var sourceClient = new ClientExtBuilder("source-client", "Source Client")
            .WithId(1)
            .Build();

        var cloneRequest = new ClientDtoClone
        {
            Id = 1,
            ClientId = "cloned-client",
            ClientName = "Cloned Client",
            SystemPermissionEnvironmentId = 2
        };

        _clientStorage.GetByIdAsync(1).Returns(sourceClient);
        _permissionChecker.GetAccessRoleOrThrowIfNoAccessToEnvAsync(_user, 2, EntityAccessType.Create, "Application")
            .Returns(SystemPermissionRoleType.Writer);
        _permissionChecker.GetAccessRoleOrThrowIfNoAccessToEnvAsync(_user, sourceClient.SystemPermissionEnvironmentId, EntityAccessType.Read, Arg.Any<string>())
            .Returns<SystemPermissionRoleType>(x => throw new EntityAccessException(_user, sourceClient.ToString()!, EntityAccessType.Read));

        // Act & Assert
        Assert.ThrowsAsync<EntityAccessException>(() => _sut.CloneAsync(_user, cloneRequest));
    }

    [Test]
    public void CreateClientCopy_WithBasicProperties_CopiesCorrectly()
    {
        // Arrange
        var source = new ClientExtBuilder("source-client", "Source Client")
            .WithId(1)
            .Build();
        source.Description = "Test Description";
        source.Enabled = true;
        source.RequireClientSecret = true;
        source.RequirePkce = true;
        source.AccessTokenType = (int)ClientAccessTokenType.Jwt;
        source.AllowOfflineAccess = true;

        var env = new SystemPermissionEnvironment
        {
            Id = 2,
            Environment = SystemPermissionEnvironmentNames.QA,
            SystemPermission = new SystemPermission { Name = "Test", Description = "Test" }
        };

        // Act
        var copy = ClientDtoCloneRepository.CreateClientCopy(source, env);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(copy.Id, Is.Zero);
            Assert.That(copy.Description, Is.EqualTo(source.Description));
            Assert.That(copy.Enabled, Is.EqualTo(source.Enabled));
            Assert.That(copy.RequireClientSecret, Is.EqualTo(source.RequireClientSecret));
            Assert.That(copy.RequirePkce, Is.EqualTo(source.RequirePkce));
            Assert.That(copy.AccessTokenType, Is.EqualTo(source.AccessTokenType));
            Assert.That(copy.AllowOfflineAccess, Is.EqualTo(source.AllowOfflineAccess));
            Assert.That(copy.SystemPermissionEnvironmentId, Is.EqualTo(env.Id));
            Assert.That(copy.SystemPermissionEnvironment, Is.EqualTo(env));
        }
    }

    [Test]
    public void CopyGrantTypes_WithGrantTypes_CopiesAll()
    {
        // Arrange
        var source = new ClientExtBuilder("source-client", "Source Client")
            .WithGrantType(ClientGrantTypeNames.Grant_Code)
            .WithGrantType(ClientGrantTypeNames.Grant_ClientCredentials)
            .Build();

        var copy = new ClientExtBuilder("copy", "Copy").Build();

        // Act
        ClientDtoCloneRepository.CopyGrantTypes(source, copy);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(copy.AllowedGrantTypes, Is.Not.Null);
            Assert.That(copy.AllowedGrantTypes, Has.Count.EqualTo(2));
            Assert.That(copy.AllowedGrantTypes.Any(gt => gt.GrantType == ClientGrantTypeNames.Grant_Code), Is.True);
            Assert.That(copy.AllowedGrantTypes.Any(gt => gt.GrantType == ClientGrantTypeNames.Grant_ClientCredentials), Is.True);
            Assert.That(copy.AllowedGrantTypes.All(gt => gt.Id == 0), Is.True);
            Assert.That(copy.AllowedGrantTypes.All(gt => gt.ClientId == 0), Is.True);
        }
    }

    [Test]
    public void CopyGrantTypes_WithNullGrantTypes_DoesNotCopy()
    {
        // Arrange
        var source = new ClientExtBuilder("source-client", "Source Client").Build();
        source.AllowedGrantTypes = null;

        var copy = new ClientExtBuilder("copy", "Copy").Build();

        // Act
        ClientDtoCloneRepository.CopyGrantTypes(source, copy);

        // Assert
        Assert.That(copy.AllowedGrantTypes, Is.Empty);
    }

    [Test]
    public void CopyRedirectUris_WithLocalhostUris_CopiesOnlyLocalhost()
    {
        // Arrange
        var source = new ClientExtBuilder("source-client", "Source Client")
            .WithRedirectUri("http://localhost/callback")
            .WithRedirectUri("http://127.0.0.1:8080/callback")
            .WithRedirectUri("https://example.com/callback")
            .WithRedirectUri("http://localhost:3000/callback")
            .Build();

        var copy = new ClientExtBuilder("copy", "Copy").Build();

        // Act
        ClientDtoCloneRepository.CopyRedirectUris(source, copy);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(copy.RedirectUris, Is.Not.Null);
            Assert.That(copy.RedirectUris, Has.Count.EqualTo(3));
            Assert.That(copy.RedirectUris.Any(ru => ru.RedirectUri == "https://example.com/callback"), Is.False);
            Assert.That(copy.RedirectUris.All(ru => ru.Id == 0), Is.True);
            Assert.That(copy.RedirectUris.All(ru => ru.ClientId == 0), Is.True);
        }
    }

    [Test]
    public void CopyRedirectUris_WithNullRedirectUris_DoesNotCopy()
    {
        // Arrange
        var source = new ClientExtBuilder("source-client", "Source Client").Build();
        source.RedirectUris = null;

        var copy = new ClientExtBuilder("copy", "Copy").Build();

        // Act
        ClientDtoCloneRepository.CopyRedirectUris(source, copy);

        // Assert
        Assert.That(copy.RedirectUris, Is.Empty);
    }

    [Test]
    public void CopyOidcScopes_WithMixedScopes_CopiesOnlyOidcScopes()
    {
        // Arrange
        var source = new ClientExtBuilder("source-client", "Source Client")
            .WithScope("openid")
            .WithScope("profile")
            .WithScope("api.scope1")
            .WithScope("email")
            .Build();

        var copy = new ClientExtBuilder("copy", "Copy").Build();

        // Act
        ClientDtoCloneRepository.CopyOidcScopes(source, copy);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(copy.AllowedScopes, Is.Not.Null);
            Assert.That(copy.AllowedScopes, Has.Count.EqualTo(3));
            Assert.That(copy.AllowedScopes.Any(s => s.Scope == "openid"), Is.True);
            Assert.That(copy.AllowedScopes.Any(s => s.Scope == "profile"), Is.True);
            Assert.That(copy.AllowedScopes.Any(s => s.Scope == "email"), Is.True);
            Assert.That(copy.AllowedScopes.Any(s => s.Scope == "api.scope1"), Is.False);
            Assert.That(copy.AllowedScopes.All(s => s.Id == 0), Is.True);
            Assert.That(copy.AllowedScopes.All(s => s.ClientId == 0), Is.True);
        }
    }

    [Test]
    public void CopyOidcScopes_WithNullScopes_DoesNotCopy()
    {
        // Arrange
        var source = new ClientExtBuilder("source-client", "Source Client").Build();
        source.AllowedScopes = null;

        var copy = new ClientExtBuilder("copy", "Copy").Build();

        // Act
        ClientDtoCloneRepository.CopyOidcScopes(source, copy);

        // Assert
        Assert.That(copy.AllowedScopes, Is.Empty);
    }

    [Test]
    public void CopyRoles_WithRolesAndMappings_CopiesRolesWithoutMappings()
    {
        // Arrange
        var mappings = new List<ClientRoleMapping>
        {
            new() { Id = 1, ClientRoleId = 1, MappingType = ClientRoleMapType.UserObjectId, Value = "user1" },
            new() { Id = 2, ClientRoleId = 1, MappingType = ClientRoleMapType.SecurityGroup, Value = "group1" }
        };

        var source = new ClientExtBuilder("source-client", "Source Client")
            .WithRole("Role1", mappings)
            .WithRole("Role2", new List<ClientRoleMapping>())
            .Build();

        var copy = new ClientExtBuilder("copy", "Copy").Build();

        // Act
        ClientDtoCloneRepository.CopyRoles(source, copy);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(copy.Roles, Is.Not.Null);
            Assert.That(copy.Roles, Has.Count.EqualTo(2));
            Assert.That(copy.Roles.Any(r => r.RoleName == "Role1"), Is.True);
            Assert.That(copy.Roles.Any(r => r.RoleName == "Role2"), Is.True);
            Assert.That(copy.Roles.All(r => r.Mappings == null || r.Mappings.Count == 0), Is.True);
        }
    }

    [Test]
    public void CopyRoles_WithNoRoles_CreatesEmptyList()
    {
        // Arrange
        var source = new ClientExtBuilder("source-client", "Source Client").Build();
        var copy = new ClientExtBuilder("copy", "Copy").Build();

        // Act
        ClientDtoCloneRepository.CopyRoles(source, copy);

        // Assert
        Assert.That(copy.Roles, Is.Not.Null);
        Assert.That(copy.Roles, Is.Empty);
    }

    [Test]
    [TestCase("http://localhost/callback")]
    [TestCase("http://localhost:3000/callback")]
    [TestCase("https://localhost/callback")]
    [TestCase("http://127.0.0.1/callback")]
    [TestCase("http://127.0.0.1:8080/callback")]
    [TestCase("ftp://localhost")]
    [TestCase("aaa://localhost")]
    public void IsLocalHostUri_WithLocalhostUri_ReturnsTrue(string uri)
    {
        // Act & Assert
        Assert.That(ClientDtoCloneRepository.IsLocalHostUri(uri), Is.True);
    }

    [Test]
    [TestCase("http://[::1]/callback")]
    [TestCase("http://[::1]:5000/callback")]
    [TestCase("https://example.com/callback")]
    [TestCase("http://example.com:3000/callback")]
    [TestCase("https://192.168.1.1/callback")]
    [TestCase("http://10.0.0.1:8080/callback")]
    [TestCase("aaa://test")]
    public void IsLocalHostUri_WithNonLocalhostUri_ReturnsFalse(string uri)
    {
        // Act & Assert
        Assert.That(ClientDtoCloneRepository.IsLocalHostUri(uri), Is.False);
    }

    [Test]
    [TestCase("")]
    [TestCase(null)]
    [TestCase("not-a-uri")]
    [TestCase("aaa://test")]
    public void IsLocalHostUri_WithInvalidUri_ReturnsFalse(string uri)
    {
        // Act & Assert
        Assert.That(ClientDtoCloneRepository.IsLocalHostUri(uri!), Is.False);
    }

    [Test]
    public void CreateClientCopy_DoesNotCopySecrets()
    {
        // Arrange
        var source = new ClientExtBuilder("source-client", "Source Client")
            .WithSecret("secret1")
            .WithSecret("secret2")
            .Build();

        var env = new SystemPermissionEnvironment
        {
            Id = 2,
            Environment = SystemPermissionEnvironmentNames.QA,
            SystemPermission = new SystemPermission { Name = "Test", Description = "Test" }
        };

        // Act
        var copy = ClientDtoCloneRepository.CreateClientCopy(source, env);

        // Assert
        Assert.That(copy.ClientSecrets, Is.Null.Or.Empty);
    }

    [Test]
    public void CreateClientCopy_DoesNotCopyCorsOrigins()
    {
        // Arrange
        var source = new ClientExtBuilder("source-client", "Source Client")
            .WithCorsOrigin("https://example.com")
            .WithCorsOrigin("https://another.com")
            .Build();

        var env = new SystemPermissionEnvironment
        {
            Id = 2,
            Environment = SystemPermissionEnvironmentNames.QA,
            SystemPermission = new SystemPermission { Name = "Test", Description = "Test" }
        };

        // Act
        var copy = ClientDtoCloneRepository.CreateClientCopy(source, env);

        // Assert
        Assert.That(copy.AllowedCorsOrigins, Is.Null.Or.Empty);
    }

    [Test]
    public void CreateClientCopy_DoesNotCopyEntraApps()
    {
        // Arrange
        var source = new ClientExtBuilder("source-client", "Source Client")
            .WithEntraApp("app-id-1", "App 1")
            .WithEntraApp("app-id-2", "App 2")
            .Build();

        var env = new SystemPermissionEnvironment
        {
            Id = 2,
            Environment = SystemPermissionEnvironmentNames.QA,
            SystemPermission = new SystemPermission { Name = "Test", Description = "Test" }
        };

        // Act
        var copy = ClientDtoCloneRepository.CreateClientCopy(source, env);

        // Assert
        Assert.That(copy.EntraApps, Is.Null.Or.Empty);
    }

    [Test]
    public void CreateClientCopy_SetsCreatedTimestamp()
    {
        // Arrange
        var source = new ClientExtBuilder("source-client", "Source Client").Build();
        var env = new SystemPermissionEnvironment
        {
            Id = 2,
            Environment = SystemPermissionEnvironmentNames.QA,
            SystemPermission = new SystemPermission { Name = "Test", Description = "Test" }
        };
        var beforeCreate = DateTime.UtcNow;

        // Act
        var copy = ClientDtoCloneRepository.CreateClientCopy(source, env);

        // Assert
        var afterCreate = DateTime.UtcNow;
        using (Assert.EnterMultipleScope())
        {
            Assert.That(copy.Created, Is.GreaterThanOrEqualTo(beforeCreate));
            Assert.That(copy.Created, Is.LessThanOrEqualTo(afterCreate));
        }
    }

    [Test]
    public void CreateClientCopy_ResetsIdToZero()
    {
        // Arrange
        var source = new ClientExtBuilder("source-client", "Source Client")
           .WithId(123)
           .Build();

        var env = new SystemPermissionEnvironment
        {
            Id = 2,
            Environment = SystemPermissionEnvironmentNames.QA,
            SystemPermission = new SystemPermission { Name = "Test", Description = "Test" }
        };

        // Act
        var copy = ClientDtoCloneRepository.CreateClientCopy(source, env);

        // Assert
        Assert.That(copy.Id, Is.Zero);
    }
}
