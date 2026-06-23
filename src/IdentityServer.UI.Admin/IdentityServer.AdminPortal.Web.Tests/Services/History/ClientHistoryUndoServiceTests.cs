// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

#nullable enable

using NSubstitute;
using IdentityServer.Abstraction.DTO.Clients;
using IdentityServer.Abstraction.DTO.History;
using IdentityServer.Abstraction.Entities.IdentityServerConfig;
using IdentityServer.Abstraction.Enums;
using IdentityServer.AdminPortal.Web.Services;
using IdentityServer.AdminPortal.Web.Services.History;

namespace IdentityServer.AdminPortal.Web.Tests.Services.History;

[TestFixture]
public class ClientHistoryUndoServiceTests
{
    private IAdminApiService _mockAdminApiService = null!;
    private ClientHistoryUndoService _sut = null!;

    [SetUp]
    public void Setup()
    {
        _mockAdminApiService = Substitute.For<IAdminApiService>();
        _sut = new ClientHistoryUndoService(_mockAdminApiService);
    }

    #region SupportedEntityTypes Tests

    [Test]
    public void SupportedEntityTypes_ContainsExpectedTypes()
    {
        // Act
        var supportedTypes = _sut.SupportedEntityTypes;

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(supportedTypes, Does.Contain(HistoryEntryDtoExtensions.KnownEntityTypes.Client));
            Assert.That(supportedTypes, Does.Contain(HistoryEntryDtoExtensions.KnownEntityTypes.ClientRedirectUri));
            Assert.That(supportedTypes, Does.Contain(HistoryEntryDtoExtensions.KnownEntityTypes.ClientPostLogoutRedirectUri));
            Assert.That(supportedTypes, Does.Contain(HistoryEntryDtoExtensions.KnownEntityTypes.ClientCorsOrigin));
            Assert.That(supportedTypes, Does.Contain(HistoryEntryDtoExtensions.KnownEntityTypes.ClientGrantType));
            Assert.That(supportedTypes, Does.Contain(HistoryEntryDtoExtensions.KnownEntityTypes.ClientScope));
            Assert.That(supportedTypes, Does.Contain(HistoryEntryDtoExtensions.KnownEntityTypes.ClientRole));
            Assert.That(supportedTypes, Does.Contain(HistoryEntryDtoExtensions.KnownEntityTypes.ClientRoleMapping));
            Assert.That(supportedTypes, Does.Contain(HistoryEntryDtoExtensions.KnownEntityTypes.ClientEntraApp));
            Assert.That(supportedTypes, Does.Not.Contain(HistoryEntryDtoExtensions.KnownEntityTypes.ClientSecret));
        }
    }

    #endregion

    #region CanHandle Tests

    [TestCase(HistoryEntryDtoExtensions.KnownEntityTypes.Client, true)]
    [TestCase(HistoryEntryDtoExtensions.KnownEntityTypes.ClientRedirectUri, true)]
    [TestCase(HistoryEntryDtoExtensions.KnownEntityTypes.ClientPostLogoutRedirectUri, true)]
    [TestCase(HistoryEntryDtoExtensions.KnownEntityTypes.ClientCorsOrigin, true)]
    [TestCase(HistoryEntryDtoExtensions.KnownEntityTypes.ClientGrantType, true)]
    [TestCase(HistoryEntryDtoExtensions.KnownEntityTypes.ClientScope, true)]
    [TestCase(HistoryEntryDtoExtensions.KnownEntityTypes.ClientRole, true)]
    [TestCase(HistoryEntryDtoExtensions.KnownEntityTypes.ClientRoleMapping, true)]
    [TestCase(HistoryEntryDtoExtensions.KnownEntityTypes.ClientEntraApp, true)]
    [TestCase(HistoryEntryDtoExtensions.KnownEntityTypes.ClientSecret, false)]
    [TestCase(HistoryEntryDtoExtensions.KnownEntityTypes.ApiResource, false)]
    [TestCase("UnknownType", false)]
    public void CanHandle_WithEntityType_ReturnsExpectedResult(string entityType, bool expectedResult)
    {
        // Act
        var result = _sut.CanHandle(entityType);

        // Assert
        Assert.That(result, Is.EqualTo(expectedResult));
    }

    [Test]
    public void CanHandle_IsCaseInsensitive()
    {
        // Act & Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(_sut.CanHandle(HistoryEntryDtoExtensions.KnownEntityTypes.ClientRole.ToLowerInvariant()), Is.True);
            Assert.That(_sut.CanHandle(HistoryEntryDtoExtensions.KnownEntityTypes.ClientRole.ToUpperInvariant()), Is.True);
            Assert.That(_sut.CanHandle(HistoryEntryDtoExtensions.KnownEntityTypes.ClientRole), Is.True);
        }
    }

    #endregion

    #region CanUndo - Base Eligibility Tests

    [Test]
    public void CanUndo_WithCreatedEvent_ReturnsIneligible()
    {
        // Arrange
        var entry = CreateHistoryEntry(HistoryEventType.Created, HistoryEntryDtoExtensions.KnownEntityTypes.ClientScope);
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
    public void CanUndo_WithClientSecretEntityType_ReturnsIneligible()
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
    public void CanUndo_WithDeletedClientParentEntity_ReturnsIneligible()
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
    public void CanUndo_WithNullCurrentEntity_ReturnsIneligible()
    {
        // Arrange
        var entry = CreateHistoryEntry(HistoryEventType.Updated, HistoryEntryDtoExtensions.KnownEntityTypes.Client);
        entry.Changes.Add(new FieldChangeDto("ClientName", "NewName", "OldName"));

        // Act
        var result = _sut.CanUndo(entry, null);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result.CanUndo, Is.False);
            Assert.That(result.Reason, Does.Contain("Parent entity not loaded"));
        }
    }

    #endregion

    #region CanUndo - Conflict Detection Tests

    [Test]
    public void CanUndo_WithDeletedRedirectUri_WhenNoConflict_ReturnsEligible()
    {
        // Arrange
        var entry = CreateHistoryEntry(HistoryEventType.Deleted, HistoryEntryDtoExtensions.KnownEntityTypes.ClientRedirectUri);
        entry.Changes.Add(new FieldChangeDto("RedirectUri", null, "https://example.com/callback"));

        var currentClient = CreateTestClient();
        currentClient.RedirectUris.Add(new ClientPropertyRedirectUriDtoRead { RedirectUri = "https://different.com/callback" });

        // Act
        var result = _sut.CanUndo(entry, currentClient);

        // Assert
        Assert.That(result.CanUndo, Is.True);
    }

    [Test]
    public void CanUndo_WithDeletedRedirectUri_WhenDuplicateExists_ReturnsIneligible()
    {
        // Arrange
        var entry = CreateHistoryEntry(HistoryEventType.Deleted, HistoryEntryDtoExtensions.KnownEntityTypes.ClientRedirectUri);
        entry.Changes.Add(new FieldChangeDto("RedirectUri", null, "https://example.com/callback"));

        var currentClient = CreateTestClient();
        currentClient.RedirectUris.Add(new ClientPropertyRedirectUriDtoRead { RedirectUri = "https://example.com/callback" });

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
    public void CanUndo_WithDeletedRedirectUri_WhenDuplicateExistsCaseInsensitive_ReturnsIneligible()
    {
        // Arrange
        var entry = CreateHistoryEntry(HistoryEventType.Deleted, HistoryEntryDtoExtensions.KnownEntityTypes.ClientRedirectUri);
        entry.Changes.Add(new FieldChangeDto("RedirectUri", null, "HTTPS://EXAMPLE.COM/CALLBACK"));

        var currentClient = CreateTestClient();
        currentClient.RedirectUris.Add(new ClientPropertyRedirectUriDtoRead { RedirectUri = "https://example.com/callback" });

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
    public void CanUndo_WithDeletedPostLogoutRedirectUri_WhenNoConflict_ReturnsEligible()
    {
        // Arrange
        var entry = CreateHistoryEntry(HistoryEventType.Deleted, HistoryEntryDtoExtensions.KnownEntityTypes.ClientPostLogoutRedirectUri);
        entry.Changes.Add(new FieldChangeDto("PostLogoutRedirectUri", null, "https://example.com/signout"));

        var currentClient = CreateTestClient();
        currentClient.PostLogoutRedirectUris.Add(new ClientPropertyPostLogoutRedirectUriDtoRead { PostLogoutRedirectUri = "https://different.com/signout" });

        // Act
        var result = _sut.CanUndo(entry, currentClient);

        // Assert
        Assert.That(result.CanUndo, Is.True);
    }

    [Test]
    public void CanUndo_WithDeletedPostLogoutRedirectUri_WhenDuplicateExists_ReturnsIneligible()
    {
        // Arrange
        var entry = CreateHistoryEntry(HistoryEventType.Deleted, HistoryEntryDtoExtensions.KnownEntityTypes.ClientPostLogoutRedirectUri);
        entry.Changes.Add(new FieldChangeDto("PostLogoutRedirectUri", null, "https://example.com/signout"));

        var currentClient = CreateTestClient();
        currentClient.PostLogoutRedirectUris.Add(new ClientPropertyPostLogoutRedirectUriDtoRead { PostLogoutRedirectUri = "https://example.com/signout" });

        // Act
        var result = _sut.CanUndo(entry, currentClient);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result.CanUndo, Is.False);
            Assert.That(result.Reason, Does.Contain("post-logout redirect URI with this value already exists"));
        }
    }

    [Test]
    public void CanUndo_WithDeletedCorsOrigin_WhenNoConflict_ReturnsEligible()
    {
        // Arrange
        var entry = CreateHistoryEntry(HistoryEventType.Deleted, HistoryEntryDtoExtensions.KnownEntityTypes.ClientCorsOrigin);
        entry.Changes.Add(new FieldChangeDto("Origin", null, "https://example.com"));

        var currentClient = CreateTestClient();
        currentClient.AllowedCorsOrigins.Add(new ClientPropertyCorsOriginDtoRead { Origin = "https://different.com" });

        // Act
        var result = _sut.CanUndo(entry, currentClient);

        // Assert
        Assert.That(result.CanUndo, Is.True);
    }

    [Test]
    public void CanUndo_WithDeletedCorsOrigin_WhenDuplicateExists_ReturnsIneligible()
    {
        // Arrange
        var entry = CreateHistoryEntry(HistoryEventType.Deleted, HistoryEntryDtoExtensions.KnownEntityTypes.ClientCorsOrigin);
        entry.Changes.Add(new FieldChangeDto("Origin", null, "https://example.com"));

        var currentClient = CreateTestClient();
        currentClient.AllowedCorsOrigins.Add(new ClientPropertyCorsOriginDtoRead { Origin = "https://example.com" });

        // Act
        var result = _sut.CanUndo(entry, currentClient);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result.CanUndo, Is.False);
            Assert.That(result.Reason, Does.Contain("CORS origin with this value already exists"));
        }
    }

    [Test]
    public void CanUndo_WithDeletedGrantType_WhenNoConflict_ReturnsEligible()
    {
        // Arrange
        var entry = CreateHistoryEntry(HistoryEventType.Deleted, HistoryEntryDtoExtensions.KnownEntityTypes.ClientGrantType);
        entry.Changes.Add(new FieldChangeDto("GrantType", null, "authorization_code"));

        var currentClient = CreateTestClient();
        currentClient.AllowedGrantTypes.Add(new ClientPropertyGrantDtoRead { GrantType = "client_credentials" });

        // Act
        var result = _sut.CanUndo(entry, currentClient);

        // Assert
        Assert.That(result.CanUndo, Is.True);
    }

    [Test]
    public void CanUndo_WithDeletedGrantType_WhenDuplicateExists_ReturnsIneligible()
    {
        // Arrange
        var entry = CreateHistoryEntry(HistoryEventType.Deleted, HistoryEntryDtoExtensions.KnownEntityTypes.ClientGrantType);
        entry.Changes.Add(new FieldChangeDto("GrantType", null, "authorization_code"));

        var currentClient = CreateTestClient();
        currentClient.AllowedGrantTypes.Add(new ClientPropertyGrantDtoRead { GrantType = "authorization_code" });

        // Act
        var result = _sut.CanUndo(entry, currentClient);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result.CanUndo, Is.False);
            Assert.That(result.Reason, Does.Contain("grant type with this value already exists"));
        }
    }

    [Test]
    public void CanUndo_WithDeletedScope_WhenNoConflict_ReturnsEligible()
    {
        // Arrange
        var entry = CreateHistoryEntry(HistoryEventType.Deleted, HistoryEntryDtoExtensions.KnownEntityTypes.ClientScope);
        entry.Changes.Add(new FieldChangeDto("Scope", null, "api.read"));

        var currentClient = CreateTestClient();
        currentClient.AllowedScopes.Add(new ClientPropertyScopeDtoRead { Scope = "api.write" });

        // Act
        var result = _sut.CanUndo(entry, currentClient);

        // Assert
        Assert.That(result.CanUndo, Is.True);
    }

    [Test]
    public void CanUndo_WithDeletedScope_WhenDuplicateExists_ReturnsIneligible()
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
    public void CanUndo_WithDeletedClientRole_WhenNoConflict_ReturnsEligible()
    {
        // Arrange
        var entry = CreateHistoryEntry(HistoryEventType.Deleted, HistoryEntryDtoExtensions.KnownEntityTypes.ClientRole);
        entry.Changes.Add(new FieldChangeDto("RoleName", null, "admin"));

        var currentClient = CreateTestClient();
        currentClient.Roles.Add(new ClientPropertyRoleDtoRead { RoleName = "reader" });

        // Act
        var result = _sut.CanUndo(entry, currentClient);

        // Assert
        Assert.That(result.CanUndo, Is.True);
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
        entry.Changes.Add(new FieldChangeDto("ClientName", "NewName", "OldName"));

        var currentClient = CreateTestClient();

        // Act
        var result = _sut.CanUndo(entry, currentClient);

        // Assert
        Assert.That(result.CanUndo, Is.True);
    }

    #endregion

    #region ExecuteUndoAsync - Update Client Tests

    [Test]
    public async Task ExecuteUndoAsync_WithUpdatedClient_CallsUpdateClient()
    {
        // Arrange
        var entry = CreateHistoryEntry(HistoryEventType.Updated, HistoryEntryDtoExtensions.KnownEntityTypes.Client);
        entry.Changes.Add(new FieldChangeDto("ClientName", "NewClientName", "OldClientName"));
        entry.Changes.Add(new FieldChangeDto("Description", "NewDescription", "OldDescription"));
        entry.Changes.Add(new FieldChangeDto("Enabled", "True", "False"));
        entry.Changes.Add(new FieldChangeDto("RequirePkce", "False", "True"));
        entry.Changes.Add(new FieldChangeDto("RequireClientSecret", "False", "True"));
        entry.Changes.Add(new FieldChangeDto("AllowOfflineAccess", "True", "False"));

        var currentClient = CreateTestClient();
        var expectedResult = new ClientDtoRead { Id = 1, ClientId = "test-client", ClientName = "OldClientName" };
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
                dto.ClientName == "OldClientName" &&
                dto.Description == "OldDescription" &&
                dto.Enabled == false &&
                dto.RequirePkce == true &&
                dto.RequireClientSecret == true &&
                dto.AllowOfflineAccess == false));
        }
    }

    [Test]
    public async Task ExecuteUndoAsync_WithUpdatedClientPartialFields_UpdatesOnlyProvidedFields()
    {
        // Arrange
        var entry = CreateHistoryEntry(HistoryEventType.Updated, HistoryEntryDtoExtensions.KnownEntityTypes.Client);
        entry.Changes.Add(new FieldChangeDto("ClientName", "NewClientName", "OldClientName"));

        var currentClient = CreateTestClient();
        var expectedResult = new ClientDtoRead { Id = 1, ClientId = "test-client", ClientName = "OldClientName" };
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
                dto.ClientName == "OldClientName" &&
                dto.Description == null &&
                dto.Enabled == null));
        }
    }

    [Test]
    public async Task ExecuteUndoAsync_WithUpdatedClient_WhenApiCallFails_ReturnsError()
    {
        // Arrange
        var entry = CreateHistoryEntry(HistoryEventType.Updated, HistoryEntryDtoExtensions.KnownEntityTypes.Client);
        entry.Changes.Add(new FieldChangeDto("ClientName", "NewClientName", "OldClientName"));

        var currentClient = CreateTestClient();
        _mockAdminApiService.UpdateClient(Arg.Any<ClientDtoUpdate>())
            .Returns(new ApiCallResult<ClientDtoRead>("Update failed"));

        // Act
        var result = await _sut.ExecuteUndoAsync(entry, currentClient);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result.IsSuccess, Is.False);
            Assert.That(result.ErrorMessage, Does.Contain("Update failed"));
        }
    }

    #endregion

    #region ExecuteUndoAsync - Delete (Recreate) RedirectUri Tests

    [Test]
    public async Task ExecuteUndoAsync_WithDeletedRedirectUri_CallsAddClientRedirectUri()
    {
        // Arrange
        var entry = CreateHistoryEntry(HistoryEventType.Deleted, HistoryEntryDtoExtensions.KnownEntityTypes.ClientRedirectUri);
        entry.Changes.Add(new FieldChangeDto("RedirectUri", null, "https://example.com/callback"));

        var currentClient = CreateTestClient();
        var expectedRedirectUriResult = new ClientPropertyRedirectUriDtoRead { Id = 1, RedirectUri = "https://example.com/callback" };
        var expectedClientResult = CreateTestClient();

        _mockAdminApiService.AddClientRedirectUri(Arg.Any<ClientPropertyRedirectUriDtoCreate>())
            .Returns(new ApiCallResult<ClientPropertyRedirectUriDtoRead>(expectedRedirectUriResult));
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
                dto.RedirectUri == "https://example.com/callback"));
            await _mockAdminApiService.Received(1).GetClient(1);
        }
    }

    [Test]
    public async Task ExecuteUndoAsync_WithDeletedRedirectUri_WhenMissingRedirectUri_ReturnsError()
    {
        // Arrange
        var entry = CreateHistoryEntry(HistoryEventType.Deleted, HistoryEntryDtoExtensions.KnownEntityTypes.ClientRedirectUri);
        // No RedirectUri change added

        var currentClient = CreateTestClient();

        // Act
        var result = await _sut.ExecuteUndoAsync(entry, currentClient);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result.IsSuccess, Is.False);
            Assert.That(result.ErrorMessage, Does.Contain("missing required RedirectUri"));
        }
    }

    [Test]
    public async Task ExecuteUndoAsync_WithDeletedRedirectUri_WhenAddFails_ReturnsError()
    {
        // Arrange
        var entry = CreateHistoryEntry(HistoryEventType.Deleted, HistoryEntryDtoExtensions.KnownEntityTypes.ClientRedirectUri);
        entry.Changes.Add(new FieldChangeDto("RedirectUri", null, "https://example.com/callback"));

        var currentClient = CreateTestClient();
        _mockAdminApiService.AddClientRedirectUri(Arg.Any<ClientPropertyRedirectUriDtoCreate>())
            .Returns(new ApiCallResult<ClientPropertyRedirectUriDtoRead>("Add failed"));

        // Act
        var result = await _sut.ExecuteUndoAsync(entry, currentClient);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result.IsSuccess, Is.False);
            Assert.That(result.ErrorMessage, Does.Contain("Add failed"));
        }
    }

    [Test]
    public async Task ExecuteUndoAsync_WithDeletedRedirectUri_WhenFetchClientFails_ReturnsError()
    {
        // Arrange
        var entry = CreateHistoryEntry(HistoryEventType.Deleted, HistoryEntryDtoExtensions.KnownEntityTypes.ClientRedirectUri);
        entry.Changes.Add(new FieldChangeDto("RedirectUri", null, "https://example.com/callback"));

        var currentClient = CreateTestClient();
        var expectedRedirectUriResult = new ClientPropertyRedirectUriDtoRead { Id = 1, RedirectUri = "https://example.com/callback" };

        _mockAdminApiService.AddClientRedirectUri(Arg.Any<ClientPropertyRedirectUriDtoCreate>())
            .Returns(new ApiCallResult<ClientPropertyRedirectUriDtoRead>(expectedRedirectUriResult));
        _mockAdminApiService.GetClient(1)
            .Returns(new ApiCallResult<ClientDtoRead>("Failed to fetch"));

        // Act
        var result = await _sut.ExecuteUndoAsync(entry, currentClient);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result.IsSuccess, Is.False);
            Assert.That(result.ErrorMessage, Does.Contain("Child entity recreated but failed to fetch updated client"));
        }
    }

    #endregion

    #region ExecuteUndoAsync - Delete (Recreate) PostLogoutRedirectUri Tests

    [Test]
    public async Task ExecuteUndoAsync_WithDeletedPostLogoutRedirectUri_CallsAddClientPostLogoutRedirectUri()
    {
        // Arrange
        var entry = CreateHistoryEntry(HistoryEventType.Deleted, HistoryEntryDtoExtensions.KnownEntityTypes.ClientPostLogoutRedirectUri);
        entry.Changes.Add(new FieldChangeDto("PostLogoutRedirectUri", null, "https://example.com/signout"));

        var currentClient = CreateTestClient();
        var expectedPostLogoutUriResult = new ClientPropertyPostLogoutRedirectUriDtoRead { Id = 1, PostLogoutRedirectUri = "https://example.com/signout" };
        var expectedClientResult = CreateTestClient();

        _mockAdminApiService.AddClientPostLogoutRedirectUri(Arg.Any<ClientPropertyPostLogoutRedirectUriDtoCreate>())
            .Returns(new ApiCallResult<ClientPropertyPostLogoutRedirectUriDtoRead>(expectedPostLogoutUriResult));
        _mockAdminApiService.GetClient(1)
            .Returns(new ApiCallResult<ClientDtoRead>(expectedClientResult));

        // Act
        var result = await _sut.ExecuteUndoAsync(entry, currentClient);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result.IsSuccess, Is.True);
            await _mockAdminApiService.Received(1).AddClientPostLogoutRedirectUri(Arg.Is<ClientPropertyPostLogoutRedirectUriDtoCreate>(dto =>
                dto.ClientId == 1 &&
                dto.PostLogoutRedirectUri == "https://example.com/signout"));
            await _mockAdminApiService.Received(1).GetClient(1);
        }
    }

    [Test]
    public async Task ExecuteUndoAsync_WithDeletedPostLogoutRedirectUri_WhenMissingPostLogoutRedirectUri_ReturnsError()
    {
        // Arrange
        var entry = CreateHistoryEntry(HistoryEventType.Deleted, HistoryEntryDtoExtensions.KnownEntityTypes.ClientPostLogoutRedirectUri);
        // No PostLogoutRedirectUri change added

        var currentClient = CreateTestClient();

        // Act
        var result = await _sut.ExecuteUndoAsync(entry, currentClient);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result.IsSuccess, Is.False);
            Assert.That(result.ErrorMessage, Does.Contain("missing required PostLogoutRedirectUri"));
        }
    }

    #endregion

    #region ExecuteUndoAsync - Delete (Recreate) CorsOrigin Tests

    [Test]
    public async Task ExecuteUndoAsync_WithDeletedCorsOrigin_CallsAddClientCorsUri()
    {
        // Arrange
        var entry = CreateHistoryEntry(HistoryEventType.Deleted, HistoryEntryDtoExtensions.KnownEntityTypes.ClientCorsOrigin);
        entry.Changes.Add(new FieldChangeDto("Origin", null, "https://example.com"));

        var currentClient = CreateTestClient();
        var expectedCorsOriginResult = new ClientPropertyCorsOriginDtoRead { Id = 1, Origin = "https://example.com" };
        var expectedClientResult = CreateTestClient();

        _mockAdminApiService.AddClientCorsUri(Arg.Any<ClientPropertyCorsOriginDtoCreate>())
            .Returns(new ApiCallResult<ClientPropertyCorsOriginDtoRead>(expectedCorsOriginResult));
        _mockAdminApiService.GetClient(1)
            .Returns(new ApiCallResult<ClientDtoRead>(expectedClientResult));

        // Act
        var result = await _sut.ExecuteUndoAsync(entry, currentClient);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result.IsSuccess, Is.True);
            await _mockAdminApiService.Received(1).AddClientCorsUri(Arg.Is<ClientPropertyCorsOriginDtoCreate>(dto =>
                dto.ClientId == 1 &&
                dto.Origin == "https://example.com"));
            await _mockAdminApiService.Received(1).GetClient(1);
        }
    }

    [Test]
    public async Task ExecuteUndoAsync_WithDeletedCorsOrigin_WhenMissingOrigin_ReturnsError()
    {
        // Arrange
        var entry = CreateHistoryEntry(HistoryEventType.Deleted, HistoryEntryDtoExtensions.KnownEntityTypes.ClientCorsOrigin);
        // No Origin change added

        var currentClient = CreateTestClient();

        // Act
        var result = await _sut.ExecuteUndoAsync(entry, currentClient);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result.IsSuccess, Is.False);
            Assert.That(result.ErrorMessage, Does.Contain("missing required Origin"));
        }
    }

    #endregion

    #region ExecuteUndoAsync - Delete (Recreate) GrantType Tests

    [Test]
    public async Task ExecuteUndoAsync_WithDeletedGrantType_CallsAddClientGrant()
    {
        // Arrange
        var entry = CreateHistoryEntry(HistoryEventType.Deleted, HistoryEntryDtoExtensions.KnownEntityTypes.ClientGrantType);
        entry.Changes.Add(new FieldChangeDto("GrantType", null, "authorization_code"));

        var currentClient = CreateTestClient();
        var expectedGrantResult = new ClientPropertyGrantDtoRead { Id = 1, GrantType = "authorization_code" };
        var expectedClientResult = CreateTestClient();

        _mockAdminApiService.AddClientGrant(Arg.Any<ClientPropertyGrantDtoCreate>())
            .Returns(new ApiCallResult<ClientPropertyGrantDtoRead>(expectedGrantResult));
        _mockAdminApiService.GetClient(1)
            .Returns(new ApiCallResult<ClientDtoRead>(expectedClientResult));

        // Act
        var result = await _sut.ExecuteUndoAsync(entry, currentClient);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result.IsSuccess, Is.True);
            await _mockAdminApiService.Received(1).AddClientGrant(Arg.Is<ClientPropertyGrantDtoCreate>(dto =>
                dto.ClientId == 1 &&
                dto.GrantType == "authorization_code"));
            await _mockAdminApiService.Received(1).GetClient(1);
        }
    }

    [Test]
    public async Task ExecuteUndoAsync_WithDeletedGrantType_WhenMissingGrantType_ReturnsError()
    {
        // Arrange
        var entry = CreateHistoryEntry(HistoryEventType.Deleted, HistoryEntryDtoExtensions.KnownEntityTypes.ClientGrantType);
        // No GrantType change added

        var currentClient = CreateTestClient();

        // Act
        var result = await _sut.ExecuteUndoAsync(entry, currentClient);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result.IsSuccess, Is.False);
            Assert.That(result.ErrorMessage, Does.Contain("missing required GrantType"));
        }
    }

    #endregion

    #region ExecuteUndoAsync - Delete (Recreate) Scope Tests

    [Test]
    public async Task ExecuteUndoAsync_WithDeletedScope_CallsAddClientScope()
    {
        // Arrange
        var entry = CreateHistoryEntry(HistoryEventType.Deleted, HistoryEntryDtoExtensions.KnownEntityTypes.ClientScope);
        entry.Changes.Add(new FieldChangeDto("Scope", null, "api.read"));

        var currentClient = CreateTestClient();
        var expectedScopeResult = new ClientPropertyScopeDtoRead { Id = 1, Scope = "api.read" };
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
    public async Task ExecuteUndoAsync_WithDeletedScope_WhenMissingScope_ReturnsError()
    {
        // Arrange
        var entry = CreateHistoryEntry(HistoryEventType.Deleted, HistoryEntryDtoExtensions.KnownEntityTypes.ClientScope);
        // No Scope change added

        var currentClient = CreateTestClient();

        // Act
        var result = await _sut.ExecuteUndoAsync(entry, currentClient);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result.IsSuccess, Is.False);
            Assert.That(result.ErrorMessage, Does.Contain("missing required Scope"));
        }
    }

    #endregion

    #region ExecuteUndoAsync - Delete (Recreate) Role Tests

    [Test]
    public async Task ExecuteUndoAsync_WithDeletedRole_CallsAddClientRole()
    {
        // Arrange
        var entry = CreateHistoryEntry(HistoryEventType.Deleted, HistoryEntryDtoExtensions.KnownEntityTypes.ClientRole);
        entry.Changes.Add(new FieldChangeDto("RoleName", null, "admin"));

        var currentClient = CreateTestClient();
        var expectedRoleResult = new ClientPropertyRoleDtoRead { Id = 1, ClientId = 1, RoleName = "admin" };
        var expectedClientResult = CreateTestClient();

        _mockAdminApiService.AddClientRole(Arg.Any<ClientPropertyRoleDtoCreate>())
            .Returns(new ApiCallResult<ClientPropertyRoleDtoRead>(expectedRoleResult));
        _mockAdminApiService.GetClient(1)
            .Returns(new ApiCallResult<ClientDtoRead>(expectedClientResult));

        // Act
        var result = await _sut.ExecuteUndoAsync(entry, currentClient);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result.IsSuccess, Is.True);
            await _mockAdminApiService.Received(1).AddClientRole(Arg.Is<ClientPropertyRoleDtoCreate>(dto =>
                dto.ClientId == 1 &&
                dto.RoleName == "admin"));
            await _mockAdminApiService.Received(1).GetClient(1);
        }
    }

    [Test]
    public async Task ExecuteUndoAsync_WithDeletedRole_WhenMissingRoleName_ReturnsError()
    {
        // Arrange
        var entry = CreateHistoryEntry(HistoryEventType.Deleted, HistoryEntryDtoExtensions.KnownEntityTypes.ClientRole);
        // No RoleName change added

        var currentClient = CreateTestClient();

        // Act
        var result = await _sut.ExecuteUndoAsync(entry, currentClient);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result.IsSuccess, Is.False);
            Assert.That(result.ErrorMessage, Does.Contain("missing required RoleName"));
        }
    }

    #endregion

    #region ExecuteUndoAsync - Delete (Recreate) RoleMapping Tests

    [Test]
    public async Task ExecuteUndoAsync_WithDeletedRoleMapping_CallsAddClientRoleMapping()
    {
        // Arrange
        var entry = CreateHistoryEntry(HistoryEventType.Deleted, HistoryEntryDtoExtensions.KnownEntityTypes.ClientRoleMapping, GetRoleMappingEntityIdentifier("admin", "test-group-id"));
        entry.Changes.Add(new FieldChangeDto("Value", null, "test-group-id"));
        entry.Changes.Add(new FieldChangeDto("MappingType", null, "SecurityGroup"));

        var currentClient = CreateTestClient();
        var existingRole1 = new ClientPropertyRoleDtoRead
        {
            Id = 456,
            ClientId = 1,
            RoleName = "admin",
        };
        currentClient.Roles.Add(existingRole1);
        var expectedMappingResult = new ClientPropertyRoleMappingDtoRead
        {
            Id = 1,
            ClientRoleId = 456,
            Value = "test-group-id",
            MappingType = ClientRoleMapType.SecurityGroup
        };
        var expectedClientResult = CreateTestClient();

        _mockAdminApiService.AddClientRoleMapping(Arg.Any<ClientPropertyRoleMappingDtoCreate>())
            .Returns(new ApiCallResult<ClientPropertyRoleMappingDtoRead>(expectedMappingResult));
        _mockAdminApiService.GetClient(1)
            .Returns(new ApiCallResult<ClientDtoRead>(expectedClientResult));

        // Act
        var result = await _sut.ExecuteUndoAsync(entry, currentClient);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result.IsSuccess, Is.True);
            await _mockAdminApiService.Received(1).AddClientRoleMapping(Arg.Is<ClientPropertyRoleMappingDtoCreate>(dto =>
                dto.ClientRoleId == 456 &&
                dto.Value == "test-group-id" &&
                dto.MappingType == ClientRoleMapType.SecurityGroup));
            await _mockAdminApiService.Received(1).GetClient(1);
        }
    }

    [Test]
    public async Task ExecuteUndoAsync_WithDeletedRoleMapping_WhenMissingRoleId_ReturnsError()
    {
        // Arrange
        var entry = CreateHistoryEntry(HistoryEventType.Deleted, HistoryEntryDtoExtensions.KnownEntityTypes.ClientRoleMapping);
        entry.Changes.Add(new FieldChangeDto("Value", null, "test-value"));
        entry.Changes.Add(new FieldChangeDto("MappingType", null, "SecurityGroup"));

        var currentClient = CreateTestClient();

        // Act
        var result = await _sut.ExecuteUndoAsync(entry, currentClient);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result.IsSuccess, Is.False);
            Assert.That(result.ErrorMessage, Does.Contain("Cannot determine role ID"));
        }
    }

    [Test]
    public async Task ExecuteUndoAsync_WithDeletedRoleMapping_WhenMissingValue_ReturnsError()
    {
        // Arrange
        var entry = CreateHistoryEntry(HistoryEventType.Deleted, HistoryEntryDtoExtensions.KnownEntityTypes.ClientRoleMapping, GetRoleMappingEntityIdentifier("admin", "test-group-id"));
        entry.Changes.Add(new FieldChangeDto("MappingType", null, "SecurityGroup"));

        var currentClient = CreateTestClient();
        var existingRole1 = new ClientPropertyRoleDtoRead
        {
            Id = 1,
            ClientId = 1,
            RoleName = "admin",
        };
        currentClient.Roles.Add(existingRole1);

        // Act
        var result = await _sut.ExecuteUndoAsync(entry, currentClient);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result.IsSuccess, Is.False);
            Assert.That(result.ErrorMessage, Does.Contain("missing required Value"));
        }
    }

    [Test]
    public async Task ExecuteUndoAsync_WithDeletedRoleMapping_WhenMissingMappingType_ReturnsError()
    {
        // Arrange
        var entry = CreateHistoryEntry(HistoryEventType.Deleted, HistoryEntryDtoExtensions.KnownEntityTypes.ClientRoleMapping, GetRoleMappingEntityIdentifier("admin", "test-group-id"));
        entry.Changes.Add(new FieldChangeDto("Value", null, "test-value"));

        var currentClient = CreateTestClient();
        var existingRole1 = new ClientPropertyRoleDtoRead
        {
            Id = 1,
            ClientId = 1,
            RoleName = "admin",
        };
        currentClient.Roles.Add(existingRole1);

        // Act
        var result = await _sut.ExecuteUndoAsync(entry, currentClient);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result.IsSuccess, Is.False);
            Assert.That(result.ErrorMessage, Does.Contain("missing or invalid MappingType"));
        }
    }

    [Test]
    public async Task ExecuteUndoAsync_WithDeletedRoleMapping_WhenInvalidMappingType_ReturnsError()
    {
        // Arrange
        var entry = CreateHistoryEntry(HistoryEventType.Deleted, HistoryEntryDtoExtensions.KnownEntityTypes.ClientRoleMapping, GetRoleMappingEntityIdentifier("admin", "test-group-id"));
        entry.Changes.Add(new FieldChangeDto("Value", null, "test-value"));
        entry.Changes.Add(new FieldChangeDto("MappingType", null, "InvalidMappingType"));

        var currentClient = CreateTestClient();
        var existingRole1 = new ClientPropertyRoleDtoRead
        {
            Id = 1,
            ClientId = 1,
            RoleName = "admin",
        };
        currentClient.Roles.Add(existingRole1);

        // Act
        var result = await _sut.ExecuteUndoAsync(entry, currentClient);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result.IsSuccess, Is.False);
            Assert.That(result.ErrorMessage, Does.Contain("missing or invalid MappingType"));
        }
    }

    [Test]
    public async Task ExecuteUndoAsync_WithDeletedRoleMapping_WhenAddFails_ReturnsError()
    {
        // Arrange
        var entry = CreateHistoryEntry(HistoryEventType.Deleted, HistoryEntryDtoExtensions.KnownEntityTypes.ClientRoleMapping, GetRoleMappingEntityIdentifier("admin", "test-group-id"));
        entry.Changes.Add(new FieldChangeDto("Value", null, "test-value"));
        entry.Changes.Add(new FieldChangeDto("MappingType", null, "SecurityGroup"));

        var currentClient = CreateTestClient();
        var existingRole1 = new ClientPropertyRoleDtoRead
        {
            Id = 1,
            ClientId = 1,
            RoleName = "admin",
        };
        currentClient.Roles.Add(existingRole1);
        _mockAdminApiService.AddClientRoleMapping(Arg.Any<ClientPropertyRoleMappingDtoCreate>())
            .Returns(new ApiCallResult<ClientPropertyRoleMappingDtoRead>("Add failed"));

        // Act
        var result = await _sut.ExecuteUndoAsync(entry, currentClient);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result.IsSuccess, Is.False);
            Assert.That(result.ErrorMessage, Does.Contain("Add failed"));
        }
    }

    [Test]
    public async Task ExecuteUndoAsync_WithDeletedRoleMapping_WhenRoleIdFromEntityIdentifier_CallsAddClientRoleMapping()
    {
        // Arrange
        var entry = CreateHistoryEntry(HistoryEventType.Deleted, HistoryEntryDtoExtensions.KnownEntityTypes.ClientRoleMapping, GetRoleMappingEntityIdentifier("TestRole", "test-group-id"));
        entry.Changes.Add(new FieldChangeDto("Value", null, "test-group-id"));
        entry.Changes.Add(new FieldChangeDto("MappingType", null, "SecurityGroup"));

        var currentClient = CreateTestClient();
        currentClient.Roles.Add(new ClientPropertyRoleDtoRead
        {
            Id = 123,
            ClientId = 1,
            RoleName = "TestRole",
            Mappings = new List<ClientPropertyRoleMappingDtoRead>()
        });

        var expectedMappingResult = new ClientPropertyRoleMappingDtoRead
        {
            Id = 1,
            ClientRoleId = 123,
            Value = "test-group-id",
            MappingType = ClientRoleMapType.SecurityGroup
        };
        var expectedClientResult = CreateTestClient();

        _mockAdminApiService.AddClientRoleMapping(Arg.Any<ClientPropertyRoleMappingDtoCreate>())
            .Returns(new ApiCallResult<ClientPropertyRoleMappingDtoRead>(expectedMappingResult));
        _mockAdminApiService.GetClient(1)
            .Returns(new ApiCallResult<ClientDtoRead>(expectedClientResult));

        // Act
        var result = await _sut.ExecuteUndoAsync(entry, currentClient);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result.IsSuccess, Is.True);
            await _mockAdminApiService.Received(1).AddClientRoleMapping(Arg.Is<ClientPropertyRoleMappingDtoCreate>(dto =>
                dto.ClientRoleId == 123 &&
                dto.Value == "test-group-id" &&
                dto.MappingType == ClientRoleMapType.SecurityGroup));
            await _mockAdminApiService.Received(1).GetClient(1);
        }
    }

    [Test]
    public async Task ExecuteUndoAsync_WithDeletedRoleMapping_WhenRoleNotFoundInEntity_ReturnsError()
    {
        // Arrange
        var entry = CreateHistoryEntry(HistoryEventType.Deleted, HistoryEntryDtoExtensions.KnownEntityTypes.ClientRoleMapping, GetRoleMappingEntityIdentifier("NonExistentRole", "test-group-id"));
        entry.Changes.Add(new FieldChangeDto("Value", null, "test-group-id"));
        entry.Changes.Add(new FieldChangeDto("MappingType", null, "SecurityGroup"));

        var currentClient = CreateTestClient();
        currentClient.Roles.Add(new ClientPropertyRoleDtoRead
        {
            Id = 123,
            ClientId = 1,
            RoleName = "DifferentRole",
            Mappings = new List<ClientPropertyRoleMappingDtoRead>()
        });

        // Act
        var result = await _sut.ExecuteUndoAsync(entry, currentClient);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result.IsSuccess, Is.False);
            Assert.That(result.ErrorMessage, Does.Contain("no longer exists"));
        }
    }

    #endregion

    #region ExecuteUndoAsync - Unsupported Operations Tests

    [Test]
    public async Task ExecuteUndoAsync_WithUnsupportedEventType_ReturnsError()
    {
        // Arrange
        var entry = CreateHistoryEntry(HistoryEventType.Created, HistoryEntryDtoExtensions.KnownEntityTypes.Client);

        var currentClient = CreateTestClient();

        // Act
        var result = await _sut.ExecuteUndoAsync(entry, currentClient);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result.IsSuccess, Is.False);
            Assert.That(result.ErrorMessage, Does.Contain("Unsupported event type"));
        }
    }

    [Test]
    public async Task ExecuteUndoAsync_WithUnsupportedEntityTypeForUpdate_ReturnsError()
    {
        // Arrange
        var entry = CreateHistoryEntry(HistoryEventType.Updated, HistoryEntryDtoExtensions.KnownEntityTypes.ClientRole);
        entry.Changes.Add(new FieldChangeDto("RoleName", "NewName", "OldName"));

        var currentClient = CreateTestClient();

        // Act
        var result = await _sut.ExecuteUndoAsync(entry, currentClient);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result.IsSuccess, Is.False);
            Assert.That(result.ErrorMessage, Does.Contain("not supported"));
        }
    }

    [Test]
    public async Task ExecuteUndoAsync_WithUnsupportedEntityTypeForDelete_ReturnsError()
    {
        // Arrange
        var entry = CreateHistoryEntry(HistoryEventType.Deleted, HistoryEntryDtoExtensions.KnownEntityTypes.ClientEntraApp);
        entry.Changes.Add(new FieldChangeDto("EntraApplicationId", null, "some-app-id"));

        var currentClient = CreateTestClient();

        // Act
        var result = await _sut.ExecuteUndoAsync(entry, currentClient);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result.IsSuccess, Is.False);
            Assert.That(result.ErrorMessage, Does.Contain("not supported"));
        }
    }

    #endregion

    #region Helper Methods

    private static HistoryEntryDto CreateHistoryEntry(HistoryEventType eventType, string entityType, string entityIdentifier = "test-entity-1")
    {
        return new HistoryEntryDto
        {
            Timestamp = DateTime.UtcNow,
            EventType = eventType,
            EntityType = entityType,
            EntityIdentifier = entityIdentifier,
            ChangedBy = "test@example.com",
            Changes = new List<FieldChangeDto>()
        };
    }

    private static string GetRoleMappingEntityIdentifier(string roleName, string value)
    {
        return $"{roleName}:{value}";
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
            ClientSecrets = new List<ClientPropertySecretDtoRead>()
        };
    }

    #endregion
}
