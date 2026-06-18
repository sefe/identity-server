#nullable enable

using NSubstitute;
using IdentityServer.Abstraction.DTO.ApiResources;
using IdentityServer.Abstraction.DTO.Clients;
using IdentityServer.Abstraction.DTO.History;
using IdentityServer.Abstraction.DTO.SystemPermissions;
using IdentityServer.Abstraction.Enums;
using IdentityServer.AdminPortal.Web.Services;
using IdentityServer.AdminPortal.Web.Services.History;

namespace IdentityServer.AdminPortal.Web.Tests.Services.History;

[TestFixture]
public class HistoryUndoServiceTests
{
    private IAdminApiService _mockAdminApiService = null!;
    private ClientHistoryUndoService _clientUndoService = null!;
    private ApiResourceHistoryUndoService _apiResourceUndoService = null!;
    private SystemPermissionHistoryUndoService _systemPermissionUndoService = null!;
    private HistoryUndoService _sut = null!;

    [SetUp]
    public void Setup()
    {
        _mockAdminApiService = Substitute.For<IAdminApiService>();
        _clientUndoService = new ClientHistoryUndoService(_mockAdminApiService);
        _apiResourceUndoService = new ApiResourceHistoryUndoService(_mockAdminApiService);
        _systemPermissionUndoService = new SystemPermissionHistoryUndoService(_mockAdminApiService);
        _sut = new HistoryUndoService(_clientUndoService, _apiResourceUndoService, _systemPermissionUndoService);
    }

    #region CanUndo - Base Eligibility Tests

    [Test]
    public void CanUndo_WithCreatedEvent_ReturnsIneligible()
    {
        // Arrange
        var entry = CreateHistoryEntry(HistoryEventType.Created, HistoryEntryDtoExtensions.KnownEntityTypes.ClientRedirectUri);
        var currentClient = CreateTestClient();

        // Act
        var result = _sut.CanUndo(entry, currentClient);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result.CanUndo, Is.False);
            Assert.That(result.Reason, Does.Contain("Created events cannot be undone"));
        }
    }

    [Test]
    public void CanUndo_WithSecretEntityType_ReturnsIneligible()
    {
        // Arrange
        var entry = CreateHistoryEntry(HistoryEventType.Deleted, HistoryEntryDtoExtensions.KnownEntityTypes.ClientSecret);
        var currentClient = CreateTestClient();

        // Act
        var result = _sut.CanUndo(entry, currentClient);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result.CanUndo, Is.False);
            Assert.That(result.Reason, Does.Contain("Secret operations cannot be undone"));
        }
    }

    [Test]
    public void CanUndo_WithApiResourceSecretEntityType_ReturnsIneligible()
    {
        // Arrange
        var entry = CreateHistoryEntry(HistoryEventType.Deleted, HistoryEntryDtoExtensions.KnownEntityTypes.ApiResourceSecret);
        var currentApiResource = CreateTestApiResource();

        // Act
        var result = _sut.CanUndo(entry, currentApiResource);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result.CanUndo, Is.False);
            Assert.That(result.Reason, Does.Contain("Secret operations cannot be undone"));
        }
    }

    [Test]
    public void CanUndo_WithDeletedParentEntity_ReturnsIneligible()
    {
        // Arrange
        var entry = CreateHistoryEntry(HistoryEventType.Deleted, HistoryEntryDtoExtensions.KnownEntityTypes.Client);
        var currentClient = CreateTestClient();

        // Act
        var result = _sut.CanUndo(entry, currentClient);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result.CanUndo, Is.False);
            Assert.That(result.Reason, Does.Contain("Parent entity deletions cannot be undone"));
        }
    }

    [Test]
    public void CanUndo_WithNullParentEntity_ReturnsIneligible()
    {
        // Arrange
        var entry = CreateHistoryEntry(HistoryEventType.Updated, HistoryEntryDtoExtensions.KnownEntityTypes.Client);
        entry.Changes.Add(new FieldChangeDto { FieldName = "ClientName", OldValue = "Old Name", NewValue = "New Name" });

        // Act
        var result = _sut.CanUndo(entry, (ClientDtoRead?)null);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result.CanUndo, Is.False);
            Assert.That(result.Reason, Does.Contain("Parent entity not loaded"));
        }
    }

    #endregion

    #region CanUndo - Client Conflict Detection Tests

    [Test]
    public void CanUndo_WithDeletedClientRedirectUri_WhenNoConflict_ReturnsEligible()
    {
        // Arrange
        var entry = CreateHistoryEntry(HistoryEventType.Deleted, HistoryEntryDtoExtensions.KnownEntityTypes.ClientRedirectUri);
        entry.Changes.Add(new FieldChangeDto("RedirectUri", null, "https://old-redirect.com"));

        var currentClient = CreateTestClient();
        currentClient.RedirectUris.Add(new ClientPropertyRedirectUriDtoRead { RedirectUri = "https://different.com" });

        // Act
        var result = _sut.CanUndo(entry, currentClient);

        // Assert
        Assert.That(result.CanUndo, Is.True);
    }

    [Test]
    public void CanUndo_WithDeletedClientRedirectUri_WhenDuplicateExists_ReturnsIneligible()
    {
        // Arrange
        var entry = CreateHistoryEntry(HistoryEventType.Deleted, HistoryEntryDtoExtensions.KnownEntityTypes.ClientRedirectUri);
        entry.Changes.Add(new FieldChangeDto("RedirectUri", null, "https://duplicate.com"));

        var currentClient = CreateTestClient();
        currentClient.RedirectUris.Add(new ClientPropertyRedirectUriDtoRead { RedirectUri = "https://duplicate.com" });

        // Act
        var result = _sut.CanUndo(entry, currentClient);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result.CanUndo, Is.False);
            Assert.That(result.Reason, Does.Contain("redirect URI with this value already exists"));
        }
    }

    [Test]
    public void CanUndo_WithDeletedClientScope_WhenDuplicateExists_ReturnsIneligible()
    {
        // Arrange
        var entry = CreateHistoryEntry(HistoryEventType.Deleted, HistoryEntryDtoExtensions.KnownEntityTypes.ClientScope);
        entry.Changes.Add(new FieldChangeDto("Scope", null, "api.read"));

        var currentClient = CreateTestClient();
        currentClient.AllowedScopes.Add(new ClientPropertyScopeDtoRead { Scope = "api.read" });

        // Act
        var result = _sut.CanUndo(entry, currentClient);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result.CanUndo, Is.False);
            Assert.That(result.Reason, Does.Contain("scope with this value already exists"));
        }
    }

    [Test]
    public void CanUndo_WithDeletedClientRole_WhenDuplicateExists_ReturnsIneligible()
    {
        // Arrange
        var entry = CreateHistoryEntry(HistoryEventType.Deleted, HistoryEntryDtoExtensions.KnownEntityTypes.ClientRole);
        entry.Changes.Add(new FieldChangeDto("RoleName", null, "admin"));

        var currentClient = CreateTestClient();
        currentClient.Roles.Add(new ClientPropertyRoleDtoRead { RoleName = "admin" });

        // Act
        var result = _sut.CanUndo(entry, currentClient);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result.CanUndo, Is.False);
            Assert.That(result.Reason, Does.Contain("role with this name already exists"));
        }
    }

    [Test]
    public void CanUndo_WithUpdatedClient_ReturnsEligible()
    {
        // Arrange
        var entry = CreateHistoryEntry(HistoryEventType.Updated, HistoryEntryDtoExtensions.KnownEntityTypes.Client);
        entry.Changes.Add(new FieldChangeDto("ClientName", "New Name", "Old Name"));

        var currentClient = CreateTestClient();

        // Act
        var result = _sut.CanUndo(entry, currentClient);

        // Assert
        Assert.That(result.CanUndo, Is.True);
    }

    #endregion

    #region CanUndo - API Resource Conflict Detection Tests

    [Test]
    public void CanUndo_WithDeletedApiResourceScope_WhenDuplicateExists_ReturnsIneligible()
    {
        // Arrange
        var entry = CreateHistoryEntry(HistoryEventType.Deleted, HistoryEntryDtoExtensions.KnownEntityTypes.ApiScope);
        entry.Changes.Add(new FieldChangeDto("Name", null, "api.read"));

        var currentApiResource = CreateTestApiResource();
        currentApiResource.Scopes.Add(new ApiResourcePropertyScopeDtoRead { Scope = "api.read" });

        // Act
        var result = _sut.CanUndo(entry, currentApiResource);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result.CanUndo, Is.False);
            Assert.That(result.Reason, Does.Contain("scope with this name already exists"));
        }
    }

    [Test]
    public void CanUndo_WithDeletedApiResourceRole_WhenDuplicateExists_ReturnsIneligible()
    {
        // Arrange
        var entry = CreateHistoryEntry(HistoryEventType.Deleted, HistoryEntryDtoExtensions.KnownEntityTypes.ApiResourceRole);
        entry.Changes.Add(new FieldChangeDto("RoleName", null, "admin"));

        var currentApiResource = CreateTestApiResource();
        currentApiResource.Roles.Add(new ApiResourcePropertyRoleDtoRead { RoleName = "admin" });

        // Act
        var result = _sut.CanUndo(entry, currentApiResource);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result.CanUndo, Is.False);
            Assert.That(result.Reason, Does.Contain("role with this name already exists"));
        }
    }

    #endregion

    #region CanUndo - System Permission Conflict Detection Tests

    [Test]
    public void CanUndo_WithDeletedSystemPermissionEnvironment_WhenDuplicateExists_ReturnsIneligible()
    {
        // Arrange
        var entry = CreateHistoryEntry(HistoryEventType.Deleted, HistoryEntryDtoExtensions.KnownEntityTypes.SystemPermissionEnvironment);
        entry.Changes.Add(new FieldChangeDto("Environment", null, "Production"));

        var currentSystemPermission = CreateTestSystemPermission();
        currentSystemPermission.Environments.Add(new SystemPermissionEnvironmentDtoRead { Environment = "Production" });

        // Act
        var result = _sut.CanUndo(entry, currentSystemPermission);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result.CanUndo, Is.False);
            Assert.That(result.Reason, Does.Contain("environment with this name already exists"));
        }
    }

    #endregion

    #region GetUndoPreview Tests

    [Test]
    public void GetUndoPreview_WithFieldChanges_ReturnsReversedChanges()
    {
        // Arrange
        var entry = CreateHistoryEntry(HistoryEventType.Updated, HistoryEntryDtoExtensions.KnownEntityTypes.Client);
        entry.Changes.Add(new FieldChangeDto("ClientName", "NewName", "OldName"));
        entry.Changes.Add(new FieldChangeDto("Description", "NewDesc", "OldDesc"));

        // Act
        var preview = _sut.GetUndoPreview(entry);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(preview.ChangesToReverse, Has.Count.EqualTo(2));
            Assert.That(preview.ChangesToReverse[0].NewValue, Is.EqualTo("OldName"));
            Assert.That(preview.ChangesToReverse[0].OldValue, Is.EqualTo("NewName"));
        }
    }

    #endregion

    #region ExecuteUndoAsync - Update Tests

    [Test]
    public async Task ExecuteUndoAsync_WithUpdatedClient_CallsUpdateClient()
    {
        // Arrange
        var entry = CreateHistoryEntry(HistoryEventType.Updated, HistoryEntryDtoExtensions.KnownEntityTypes.Client);
        entry.Changes.Add(new FieldChangeDto("ClientName", "NewName", "OldName"));
        entry.Changes.Add(new FieldChangeDto("Enabled", "True", "False"));

        var currentClient = CreateTestClient();
        var expectedResult = new ClientDtoRead { Id = 1, ClientId = "test-client", ClientName = "OldName" };
        _mockAdminApiService.UpdateClient(Arg.Any<ClientDtoUpdate>())
            .Returns(new ApiCallResult<ClientDtoRead>(expectedResult));

        // Act
        var result = await _sut.ExecuteUndoAsync(entry, currentClient);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result.IsSuccess, Is.True);
            await _mockAdminApiService.Received(1).UpdateClient(Arg.Is<ClientDtoUpdate>(dto =>
                dto.Id == 1 &&
                dto.ClientName == "OldName" &&
                dto.Enabled == false));
        }
    }

    [Test]
    public async Task ExecuteUndoAsync_WithUpdatedApiResource_CallsUpdateApiResource()
    {
        // Arrange
        var entry = CreateHistoryEntry(HistoryEventType.Updated, HistoryEntryDtoExtensions.KnownEntityTypes.ApiResource);
        entry.Changes.Add(new FieldChangeDto("DisplayName", "NewDisplayName", "OldDisplayName"));
        entry.Changes.Add(new FieldChangeDto("Enabled", "True", "False"));

        var currentApiResource = CreateTestApiResource();
        var expectedResult = new ApiResourceDtoRead { Id = 1, Name = "test-api", DisplayName = "OldDisplayName" };
        _mockAdminApiService.UpdateApiResource(Arg.Any<ApiResourceDtoUpdate>())
            .Returns(new ApiCallResult<ApiResourceDtoRead>(expectedResult));

        // Act
        var result = await _sut.ExecuteUndoAsync(entry, currentApiResource);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result.IsSuccess, Is.True);
            await _mockAdminApiService.Received(1).UpdateApiResource(Arg.Is<ApiResourceDtoUpdate>(dto =>
                dto.Id == 1 &&
                dto.DisplayName == "OldDisplayName" &&
                dto.Enabled == false));
        }
    }

    [Test]
    public async Task ExecuteUndoAsync_WithUpdatedSystemPermission_CallsUpdateSystemPermission()
    {
        // Arrange
        var entry = CreateHistoryEntry(HistoryEventType.Updated, HistoryEntryDtoExtensions.KnownEntityTypes.SystemPermission);
        entry.Changes.Add(new FieldChangeDto("Description", "NewDescription", "OldDescription"));

        var currentSystemPermission = CreateTestSystemPermission();
        var expectedResult = new SystemPermissionDtoRead { Id = 1, Name = "test-permission", Description = "OldDescription" };
        _mockAdminApiService.UpdateSystemPermission(Arg.Any<SystemPermissionDtoUpdate>())
            .Returns(new ApiCallResult<SystemPermissionDtoRead>(expectedResult));

        // Act
        var result = await _sut.ExecuteUndoAsync(entry, currentSystemPermission);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result.IsSuccess, Is.True);
            await _mockAdminApiService.Received(1).UpdateSystemPermission(Arg.Is<SystemPermissionDtoUpdate>(dto =>
                dto.Id == 1 &&
                dto.Description == "OldDescription"));
        }
    }

    #endregion

    #region ExecuteUndoAsync - Delete Tests (Recreate)

    [Test]
    public async Task ExecuteUndoAsync_WithDeletedClientRedirectUri_CallsAddClientRedirectUri()
    {
        // Arrange
        var entry = CreateHistoryEntry(HistoryEventType.Deleted, HistoryEntryDtoExtensions.KnownEntityTypes.ClientRedirectUri);
        entry.Changes.Add(new FieldChangeDto("RedirectUri", null, "https://old-redirect.com"));

        var currentClient = CreateTestClient();
        var expectedRedirectResult = new ClientPropertyRedirectUriDtoRead { Id = 1, ClientId = 1, RedirectUri = "https://old-redirect.com" };
        var expectedClientResult = CreateTestClient();
        _mockAdminApiService.AddClientRedirectUri(Arg.Any<ClientPropertyRedirectUriDtoCreate>())
            .Returns(new ApiCallResult<ClientPropertyRedirectUriDtoRead>(expectedRedirectResult));
        _mockAdminApiService.GetClient(1)
            .Returns(new ApiCallResult<ClientDtoRead>(expectedClientResult));

        // Act
        var result = await _sut.ExecuteUndoAsync(entry, currentClient);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result.IsSuccess, Is.True);
            await _mockAdminApiService.Received(1).AddClientRedirectUri(Arg.Is<ClientPropertyRedirectUriDtoCreate>(dto =>
                dto.ClientId == 1 &&
                dto.RedirectUri == "https://old-redirect.com"));
            await _mockAdminApiService.Received(1).GetClient(1);
        }
    }

    [Test]
    public async Task ExecuteUndoAsync_WithDeletedClientScope_CallsAddClientScope()
    {
        // Arrange
        var entry = CreateHistoryEntry(HistoryEventType.Deleted, HistoryEntryDtoExtensions.KnownEntityTypes.ClientScope);
        entry.Changes.Add(new FieldChangeDto("Scope", null, "api.read"));

        var currentClient = CreateTestClient();
        var expectedScopeResult = new ClientPropertyScopeDtoRead { Id = 1, ClientId = 1, Scope = "api.read" };
        var expectedClientResult = CreateTestClient();
        _mockAdminApiService.AddClientScope(Arg.Any<ClientPropertyScopeDtoCreate>())
            .Returns(new ApiCallResult<ClientPropertyScopeDtoRead>(expectedScopeResult));
        _mockAdminApiService.GetClient(1)
            .Returns(new ApiCallResult<ClientDtoRead>(expectedClientResult));

        // Act
        var result = await _sut.ExecuteUndoAsync(entry, currentClient);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result.IsSuccess, Is.True);
            await _mockAdminApiService.Received(1).AddClientScope(Arg.Is<ClientPropertyScopeDtoCreate>(dto =>
                dto.ClientId == 1 &&
                dto.Scope == "api.read"));
            await _mockAdminApiService.Received(1).GetClient(1);
        }
    }

    [Test]
    public async Task ExecuteUndoAsync_WithDeletedApiResourceRole_CallsAddApiResourceRole()
    {
        // Arrange
        var entry = CreateHistoryEntry(HistoryEventType.Deleted, HistoryEntryDtoExtensions.KnownEntityTypes.ApiResourceRole);
        entry.Changes.Add(new FieldChangeDto("RoleName", null, "admin"));

        var currentApiResource = CreateTestApiResource();
        var expectedRoleResult = new ApiResourcePropertyRoleDtoRead { Id = 1, ApiResourceId = 1, RoleName = "admin" };
        var expectedApiResourceResult = CreateTestApiResource();
        _mockAdminApiService.AddApiResourceRole(Arg.Any<ApiResourcePropertyRoleDtoCreate>())
            .Returns(new ApiCallResult<ApiResourcePropertyRoleDtoRead>(expectedRoleResult));
        _mockAdminApiService.GetApiResource(1)
            .Returns(new ApiCallResult<ApiResourceDtoRead>(expectedApiResourceResult));

        // Act
        var result = await _sut.ExecuteUndoAsync(entry, currentApiResource);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result.IsSuccess, Is.True);
            await _mockAdminApiService.Received(1).AddApiResourceRole(Arg.Is<ApiResourcePropertyRoleDtoCreate>(dto =>
                dto.ApiResourceId == 1 &&
                dto.RoleName == "admin"));
            await _mockAdminApiService.Received(1).GetApiResource(1);
        }
    }

    [Test]
    public async Task ExecuteUndoAsync_WithDeletedSystemPermissionEnvironment_CallsCreateSystemPermissionEnvironment()
    {
        // Arrange
        var entry = CreateHistoryEntry(HistoryEventType.Deleted, HistoryEntryDtoExtensions.KnownEntityTypes.SystemPermissionEnvironment);
        entry.Changes.Add(new FieldChangeDto("Environment", null, "Production"));

        var currentSystemPermission = CreateTestSystemPermission();
        var expectedEnvResult = new SystemPermissionDtoRead { Id = 1, Name = "test", Description = "test" };
        var expectedSystemPermissionResult = CreateTestSystemPermission();
        _mockAdminApiService.CreateSystemPermissionEnvironment(Arg.Any<SystemPermissionEnvironmentDtoCreate>())
            .Returns(new ApiCallResult<SystemPermissionDtoRead>(expectedEnvResult));
        _mockAdminApiService.GetSystemPermission(1)
            .Returns(new ApiCallResult<SystemPermissionDtoRead>(expectedSystemPermissionResult));

        // Act
        var result = await _sut.ExecuteUndoAsync(entry, currentSystemPermission);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result.IsSuccess, Is.True);
            await _mockAdminApiService.Received(1).CreateSystemPermissionEnvironment(Arg.Is<SystemPermissionEnvironmentDtoCreate>(dto =>
                dto.SystemPermissionId == 1 &&
                dto.Environment == "Production"));
            await _mockAdminApiService.Received(1).GetSystemPermission(1);
        }
    }

    #endregion

    #region ExecuteUndoAsync - Error Handling Tests

    [Test]
    public async Task ExecuteUndoAsync_WhenApiCallFails_ReturnsError()
    {
        // Arrange
        var entry = CreateHistoryEntry(HistoryEventType.Updated, HistoryEntryDtoExtensions.KnownEntityTypes.Client);
        entry.Changes.Add(new FieldChangeDto("ClientName", "NewName", "OldName"));

        var currentClient = CreateTestClient();
        _mockAdminApiService.UpdateClient(Arg.Any<ClientDtoUpdate>())
            .Returns(new ApiCallResult<ClientDtoRead>("Update failed"));

        // Act
        var result = await _sut.ExecuteUndoAsync(entry, currentClient);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result.IsSuccess, Is.False);
            Assert.That(result.ErrorMessage, Does.Contain("failed"));
        }
    }

    [Test]
    public async Task ExecuteUndoAsync_WithUnsupportedEntityType_ReturnsError()
    {
        // Arrange
        var entry = CreateHistoryEntry(HistoryEventType.Deleted, "UnsupportedType");
        entry.Changes.Add(new FieldChangeDto("SomeField", null, "SomeValue"));

        var currentClient = CreateTestClient();

        // Act
        var result = await _sut.ExecuteUndoAsync(entry, currentClient);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result.IsSuccess, Is.False);
            Assert.That(result.ErrorMessage, Does.Contain("undo handler doesn't support"));
        }
    }

    [Test]
    public async Task ExecuteUndoAsync_WithMissingRequiredValue_ReturnsError()
    {
        // Arrange
        var entry = CreateHistoryEntry(HistoryEventType.Deleted, HistoryEntryDtoExtensions.KnownEntityTypes.ClientRedirectUri);
        // No RedirectUri change added - missing required field

        var currentClient = CreateTestClient();

        // Act
        var result = await _sut.ExecuteUndoAsync(entry, currentClient);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result.IsSuccess, Is.False);
            Assert.That(result.ErrorMessage, Does.Contain("missing required"));
        }
    }

    #endregion

    #region Helper Methods

    private static HistoryEntryDto CreateHistoryEntry(HistoryEventType eventType, string entityType)
    {
        return new HistoryEntryDto
        {
            Timestamp = DateTime.UtcNow,
            EventType = eventType,
            EntityType = entityType,
            EntityIdentifier = "test-entity-1",
            ChangedBy = "test@example.com",
            Changes = new List<FieldChangeDto>()
        };
    }

    private static ClientDtoRead CreateTestClient()
    {
        return new ClientDtoRead
        {
            Id = 1,
            ClientId = "test-client",
            ClientName = "Test Client",
            RedirectUris = new List<ClientPropertyRedirectUriDtoRead>(),
            PostLogoutRedirectUris = new List<ClientPropertyPostLogoutRedirectUriDtoRead>(),
            AllowedCorsOrigins = new List<ClientPropertyCorsOriginDtoRead>(),
            AllowedGrantTypes = new List<ClientPropertyGrantDtoRead>(),
            AllowedScopes = new List<ClientPropertyScopeDtoRead>(),
            Roles = new List<ClientPropertyRoleDtoRead>(),
            ClientSecrets = new List<ClientPropertySecretDtoRead>(),
            EntraApps = new List<ClientPropertyEntraAppDtoRead>()
        };
    }

    private static ApiResourceDtoRead CreateTestApiResource()
    {
        return new ApiResourceDtoRead
        {
            Id = 1,
            Name = "test-api",
            DisplayName = "Test API",
            Scopes = new List<ApiResourcePropertyScopeDtoRead>(),
            Roles = new List<ApiResourcePropertyRoleDtoRead>(),
            Secrets = new List<ApiResourcePropertySecretDtoRead>()
        };
    }

    private static SystemPermissionDtoRead CreateTestSystemPermission()
    {
        return new SystemPermissionDtoRead
        {
            Id = 1,
            Name = "test-permission",
            Description = "Test Permission",
            Environments = new List<SystemPermissionEnvironmentDtoRead>()
        };
    }

    #endregion
}
