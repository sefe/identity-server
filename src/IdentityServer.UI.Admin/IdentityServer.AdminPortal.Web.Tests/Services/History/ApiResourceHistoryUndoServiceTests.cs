#nullable enable

using NSubstitute;
using IdentityServer.Abstraction.DTO.ApiResources;
using IdentityServer.Abstraction.DTO.History;
using IdentityServer.Abstraction.Entities.IdentityServerConfig;
using IdentityServer.Abstraction.Enums;
using IdentityServer.AdminPortal.Web.Services;
using IdentityServer.AdminPortal.Web.Services.History;

namespace IdentityServer.AdminPortal.Web.Tests.Services.History;

[TestFixture]
public class ApiResourceHistoryUndoServiceTests
{
    private IAdminApiService _mockAdminApiService = null!;
    private ApiResourceHistoryUndoService _sut = null!;

    [SetUp]
    public void Setup()
    {
        _mockAdminApiService = Substitute.For<IAdminApiService>();
        _sut = new ApiResourceHistoryUndoService(_mockAdminApiService);
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
            Assert.That(supportedTypes, Does.Contain(HistoryEntryDtoExtensions.KnownEntityTypes.ApiResource));
            Assert.That(supportedTypes, Does.Contain(HistoryEntryDtoExtensions.KnownEntityTypes.ApiResourceRole));
            Assert.That(supportedTypes, Does.Contain(HistoryEntryDtoExtensions.KnownEntityTypes.ApiResourceRoleMapping));
            Assert.That(supportedTypes, Does.Contain(HistoryEntryDtoExtensions.KnownEntityTypes.ApiScope));
            Assert.That(supportedTypes, Does.Not.Contain(HistoryEntryDtoExtensions.KnownEntityTypes.ApiResourceSecret));
        }
    }

    #endregion

    #region CanHandle Tests

    [TestCase(HistoryEntryDtoExtensions.KnownEntityTypes.ApiResource, true)]
    [TestCase(HistoryEntryDtoExtensions.KnownEntityTypes.ApiResourceRole, true)]
    [TestCase(HistoryEntryDtoExtensions.KnownEntityTypes.ApiResourceRoleMapping, true)]
    [TestCase(HistoryEntryDtoExtensions.KnownEntityTypes.ApiScope, true)]
    [TestCase(HistoryEntryDtoExtensions.KnownEntityTypes.ApiResourceSecret, false)]
    [TestCase(HistoryEntryDtoExtensions.KnownEntityTypes.Client, false)]
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
            Assert.That(_sut.CanHandle("apiresourceext"), Is.True);
            Assert.That(_sut.CanHandle("APIRESOURCEEXT"), Is.True);
            Assert.That(_sut.CanHandle("ApiResourceExt"), Is.True);
        }
    }

    #endregion

    #region CanUndo - Base Eligibility Tests

    [Test]
    public void CanUndo_WithCreatedEvent_ReturnsIneligible()
    {
        // Arrange
        var entry = CreateHistoryEntry(HistoryEventType.Created, HistoryEntryDtoExtensions.KnownEntityTypes.ApiScope);
        var currentApiResource = CreateTestApiResource();

        // Act
        var result = _sut.CanUndo(entry, currentApiResource);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result.CanUndo, Is.False);
            Assert.That(result.Reason, Does.Contain("Created events cannot be undone"));
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
    public void CanUndo_WithDeletedApiResourceParentEntity_ReturnsIneligible()
    {
        // Arrange
        var entry = CreateHistoryEntry(HistoryEventType.Deleted, HistoryEntryDtoExtensions.KnownEntityTypes.ApiResource);
        var currentApiResource = CreateTestApiResource();

        // Act
        var result = _sut.CanUndo(entry, currentApiResource);

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
        var entry = CreateHistoryEntry(HistoryEventType.Updated, HistoryEntryDtoExtensions.KnownEntityTypes.ApiResource);
        entry.Changes.Add(new FieldChangeDto("DisplayName", "NewName", "OldName"));

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
    public void CanUndo_WithDeletedApiScope_WhenNoConflict_ReturnsEligible()
    {
        // Arrange
        var entry = CreateHistoryEntry(HistoryEventType.Deleted, HistoryEntryDtoExtensions.KnownEntityTypes.ApiScope);
        entry.Changes.Add(new FieldChangeDto("Name", null, "api.read"));

        var currentApiResource = CreateTestApiResource();
        currentApiResource.Scopes.Add(new ApiResourcePropertyScopeDtoRead { Scope = "api.write" });

        // Act
        var result = _sut.CanUndo(entry, currentApiResource);

        // Assert
        Assert.That(result.CanUndo, Is.True);
    }

    [Test]
    public void CanUndo_WithDeletedApiScope_WhenDuplicateExists_ReturnsIneligible()
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
    public void CanUndo_WithDeletedApiScope_WhenDuplicateExistsCaseInsensitive_ReturnsIneligible()
    {
        // Arrange
        var entry = CreateHistoryEntry(HistoryEventType.Deleted, HistoryEntryDtoExtensions.KnownEntityTypes.ApiScope);
        entry.Changes.Add(new FieldChangeDto("Name", null, "API.READ"));

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
    public void CanUndo_WithDeletedApiScope_WhenScopeWithSameNameAlreadyExists_ReturnsIneligible()
    {
        // Arrange
        var entry = CreateHistoryEntry(HistoryEventType.Deleted, HistoryEntryDtoExtensions.KnownEntityTypes.ApiScope);
        entry.Changes.Add(new FieldChangeDto("Name", null, "api.access"));

        var currentApiResource = CreateTestApiResource();
        currentApiResource.Scopes.Add(new ApiResourcePropertyScopeDtoRead { Scope = "api.access" });
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
    public void CanUndo_WithDeletedApiResourceRole_WhenNoConflict_ReturnsEligible()
    {
        // Arrange
        var entry = CreateHistoryEntry(HistoryEventType.Deleted, HistoryEntryDtoExtensions.KnownEntityTypes.ApiResourceRole);
        entry.Changes.Add(new FieldChangeDto("RoleName", null, "admin"));

        var currentApiResource = CreateTestApiResource();
        currentApiResource.Roles.Add(new ApiResourcePropertyRoleDtoRead { RoleName = "reader" });

        // Act
        var result = _sut.CanUndo(entry, currentApiResource);

        // Assert
        Assert.That(result.CanUndo, Is.True);
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

    [Test]
    public void CanUndo_WithDeletedApiResourceRoleMapping_ReturnsEligible()
    {
        // Arrange
        var entry = CreateHistoryEntry(HistoryEventType.Deleted, HistoryEntryDtoExtensions.KnownEntityTypes.ApiResourceRoleMapping, GetRoleMappingEntityIdentifier("admin", "test-value"));
        entry.Changes.Add(new FieldChangeDto("Value", null, "test-value"));
        entry.Changes.Add(new FieldChangeDto("MappingType", null, "SecurityGroup"));

        var currentApiResource = CreateTestApiResource();
        var existingRole = new ApiResourcePropertyRoleDtoRead
        {
            Id = 1,
            ApiResourceId = 1,
            RoleName = "admin",
            Mappings = new List<ApiResourcePropertyRoleMappingDtoRead>()
        };
        currentApiResource.Roles.Add(existingRole);

        // Act
        var result = _sut.CanUndo(entry, currentApiResource);

        // Assert
        Assert.That(result.CanUndo, Is.True);
    }

    [Test]
    public void CanUndo_WithDeletedApiResourceRoleMapping_WhenSimilarMappingExists_ReturnsIneligible()
    {
        // Arrange
        var entry = CreateHistoryEntry(HistoryEventType.Deleted, HistoryEntryDtoExtensions.KnownEntityTypes.ApiResourceRoleMapping, GetRoleMappingEntityIdentifier("admin", "test-group-id"));
        entry.Changes.Add(new FieldChangeDto("Value", null, "test-group-id"));
        entry.Changes.Add(new FieldChangeDto("MappingType", null, "SecurityGroup"));

        var currentApiResource = CreateTestApiResource();
        var existingRole = new ApiResourcePropertyRoleDtoRead
        {
            Id = 1,
            ApiResourceId = 1,
            RoleName = "admin",
            Mappings = new List<ApiResourcePropertyRoleMappingDtoRead>
            {
                new() {
                    Id = 100,
                    ApiResourceRoleId = 1,
                    Value = "test-group-id",
                    MappingType = RoleMapType.SecurityGroup
                }
            }
        };
        currentApiResource.Roles.Add(existingRole);

        // Act
        var result = _sut.CanUndo(entry, currentApiResource);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result.CanUndo, Is.False);
            Assert.That(result.Reason, Does.Contain("role mapping with this combination already exists"));
        }
    }

    [Test]
    public void CanUndo_WithDeletedApiResourceRoleMapping_WhenClientIdMappingDuplicateExists_ReturnsIneligible()
    {
        // Arrange
        var entry = CreateHistoryEntry(HistoryEventType.Deleted, HistoryEntryDtoExtensions.KnownEntityTypes.ApiResourceRoleMapping, GetRoleMappingEntityIdentifier("editor", "client-abc-123"));
        entry.Changes.Add(new FieldChangeDto("Value", null, "client-abc-123"));
        entry.Changes.Add(new FieldChangeDto("MappingType", null, "ClientId"));

        var currentApiResource = CreateTestApiResource();
        var existingRole = new ApiResourcePropertyRoleDtoRead
        {
            Id = 2,
            ApiResourceId = 1,
            RoleName = "editor",
            Mappings = new List<ApiResourcePropertyRoleMappingDtoRead>
            {
                new() {
                    Id = 200,
                    ApiResourceRoleId = 2,
                    Value = "client-abc-123",
                    MappingType = RoleMapType.ClientId
                }
            }
        };
        currentApiResource.Roles.Add(existingRole);

        // Act
        var result = _sut.CanUndo(entry, currentApiResource);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result.CanUndo, Is.False);
            Assert.That(result.Reason, Does.Contain("role mapping with this combination already exists"));
        }
    }

    [Test]
    public void CanUndo_WithDeletedApiResourceRoleMapping_WhenUserObjectIdMappingDuplicateExists_ReturnsIneligible()
    {
        // Arrange
        var entry = CreateHistoryEntry(HistoryEventType.Deleted, HistoryEntryDtoExtensions.KnownEntityTypes.ApiResourceRoleMapping, GetRoleMappingEntityIdentifier("viewer", "user-object-id-123"));
        entry.Changes.Add(new FieldChangeDto("Value", null, "user-object-id-123"));
        entry.Changes.Add(new FieldChangeDto("MappingType", null, "UserObjectId"));

        var currentApiResource = CreateTestApiResource();
        var existingRole = new ApiResourcePropertyRoleDtoRead
        {
            Id = 3,
            ApiResourceId = 1,
            RoleName = "viewer",
            Mappings = new List<ApiResourcePropertyRoleMappingDtoRead>
            {
                new() {
                    Id = 300,
                    ApiResourceRoleId = 3,
                    Value = "user-object-id-123",
                    MappingType = RoleMapType.UserObjectId
                }
            }
        };
        currentApiResource.Roles.Add(existingRole);

        // Act
        var result = _sut.CanUndo(entry, currentApiResource);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result.CanUndo, Is.False);
            Assert.That(result.Reason, Does.Contain("role mapping with this combination already exists"));
        }
    }

    [Test]
    public void CanUndo_WithDeletedApiResourceRoleMapping_WhenNoDuplicate_ReturnsEligible()
    {
        // Arrange
        var entry = CreateHistoryEntry(HistoryEventType.Deleted, HistoryEntryDtoExtensions.KnownEntityTypes.ApiResourceRoleMapping, GetRoleMappingEntityIdentifier("admin", "different-group-id"));
        entry.Changes.Add(new FieldChangeDto("Value", null, "different-group-id"));
        entry.Changes.Add(new FieldChangeDto("MappingType", null, "SecurityGroup"));

        var currentApiResource = CreateTestApiResource();
        var existingRole = new ApiResourcePropertyRoleDtoRead
        {
            Id = 1,
            ApiResourceId = 1,
            RoleName = "admin",
            Mappings = new List<ApiResourcePropertyRoleMappingDtoRead>
            {
                new() {
                    Id = 100,
                    ApiResourceRoleId = 1,
                    Value = "test-group-id",
                    MappingType = RoleMapType.SecurityGroup
                }
            }
        };
        currentApiResource.Roles.Add(existingRole);

        // Act
        var result = _sut.CanUndo(entry, currentApiResource);

        // Assert
        Assert.That(result.CanUndo, Is.True);
    }

    [Test]
    public void CanUndo_WithDeletedApiResourceRoleMapping_WhenSameValueButDifferentType_ReturnsEligible()
    {
        // Arrange
        var entry = CreateHistoryEntry(HistoryEventType.Deleted, HistoryEntryDtoExtensions.KnownEntityTypes.ApiResourceRoleMapping, GetRoleMappingEntityIdentifier("admin", "test-value"));
        entry.Changes.Add(new FieldChangeDto("Value", null, "test-value"));
        entry.Changes.Add(new FieldChangeDto("MappingType", null, "ClientId"));

        var currentApiResource = CreateTestApiResource();
        var existingRole = new ApiResourcePropertyRoleDtoRead
        {
            Id = 1,
            ApiResourceId = 1,
            RoleName = "admin",
            Mappings = new List<ApiResourcePropertyRoleMappingDtoRead>
            {
                new() {
                    Id = 100,
                    ApiResourceRoleId = 1,
                    Value = "test-value",
                    MappingType = RoleMapType.SecurityGroup // Different type!
                }
            }
        };
        currentApiResource.Roles.Add(existingRole);

        // Act
        var result = _sut.CanUndo(entry, currentApiResource);

        // Assert
        Assert.That(result.CanUndo, Is.True);
    }

    [Test]
    public void CanUndo_WithDeletedApiResourceRoleMapping_WhenSameValueAndTypeButDifferentRole_ReturnsEligible()
    {
        // Arrange
        var entry = CreateHistoryEntry(HistoryEventType.Deleted, HistoryEntryDtoExtensions.KnownEntityTypes.ApiResourceRoleMapping, GetRoleMappingEntityIdentifier("editor", "test-value"));
        entry.Changes.Add(new FieldChangeDto("Value", null, "test-value"));
        entry.Changes.Add(new FieldChangeDto("MappingType", null, "SecurityGroup"));

        var currentApiResource = CreateTestApiResource();
        var existingRole1 = new ApiResourcePropertyRoleDtoRead
        {
            Id = 1,
            ApiResourceId = 1,
            RoleName = "admin",
            Mappings = new List<ApiResourcePropertyRoleMappingDtoRead>
            {
                new() {
                    Id = 100,
                    ApiResourceRoleId = 1,
                    Value = "test-value",
                    MappingType = RoleMapType.SecurityGroup
                }
            }
        };
        currentApiResource.Roles.Add(existingRole1);

        // Add role with ID 2 (the one referenced in the history entry)
        var existingRole2 = new ApiResourcePropertyRoleDtoRead
        {
            Id = 2,
            ApiResourceId = 1,
            RoleName = "editor",
            Mappings = new List<ApiResourcePropertyRoleMappingDtoRead>()
        };
        currentApiResource.Roles.Add(existingRole2);

        // Act
        var result = _sut.CanUndo(entry, currentApiResource);

        // Assert
        Assert.That(result.CanUndo, Is.True);
    }

    [Test]
    public void CanUndo_WithDeletedApiResourceRoleMapping_WhenRoleNoLongerExists_ReturnsIneligible()
    {
        // Arrange
        var entry = CreateHistoryEntry(HistoryEventType.Deleted, HistoryEntryDtoExtensions.KnownEntityTypes.ApiResourceRoleMapping, GetRoleMappingEntityIdentifier("nonexistent", "test-value"));
        entry.Changes.Add(new FieldChangeDto("Value", null, "test-value"));
        entry.Changes.Add(new FieldChangeDto("MappingType", null, "SecurityGroup"));

        var currentApiResource = CreateTestApiResource();
        var existingRole = new ApiResourcePropertyRoleDtoRead
        {
            Id = 1,
            ApiResourceId = 1,
            RoleName = "admin",
            Mappings = new List<ApiResourcePropertyRoleMappingDtoRead>()
        };
        currentApiResource.Roles.Add(existingRole);

        // Act
        var result = _sut.CanUndo(entry, currentApiResource);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result.CanUndo, Is.False);
            Assert.That(result.Reason, Does.Contain("no longer exists"));
        }
    }

    [Test]
    public void CanUndo_WithUpdatedApiResource_ReturnsEligible()
    {
        // Arrange
        var entry = CreateHistoryEntry(HistoryEventType.Updated, HistoryEntryDtoExtensions.KnownEntityTypes.ApiResource);
        entry.Changes.Add(new FieldChangeDto("DisplayName", "NewDisplayName", "OldDisplayName"));
        entry.Changes.Add(new FieldChangeDto("Description", "NewDescription", "OldDescription"));
        entry.Changes.Add(new FieldChangeDto("Enabled", "True", "False"));

        var currentApiResource = CreateTestApiResource();

        // Act
        var result = _sut.CanUndo(entry, currentApiResource);

        // Assert
        Assert.That(result.CanUndo, Is.True);
    }

    [Test]
    public void CanUndo_WithUpdatedApiScope_ReturnsEligible()
    {
        // Arrange
        var currentApiResource = CreateTestApiResource();
        currentApiResource.Scopes.Add(new ApiResourcePropertyScopeDtoRead { Id = 123, Scope = $"{currentApiResource.Name}.test-scope" });

        var entry = CreateHistoryEntry(HistoryEventType.Updated, HistoryEntryDtoExtensions.KnownEntityTypes.ApiScope);
        entry.Changes.Add(new FieldChangeDto("Enabled", "True", "False"));
        entry.EntityIdentifier = $"{currentApiResource.Name}.test-scope";

        // Act
        var result = _sut.CanUndo(entry, currentApiResource);

        // Assert
        Assert.That(result.CanUndo, Is.True);
    }

    [Test]
    public void CanUndo_WithUpdatedApiScope_WhenScopeNoLongerExists_ReturnsIneligible()
    {
        // Arrange
        var currentApiResource = CreateTestApiResource();
        currentApiResource.Scopes.Add(new ApiResourcePropertyScopeDtoRead { Id = 123, Scope = $"{currentApiResource.Name}.different-scope" });

        var entry = CreateHistoryEntry(HistoryEventType.Updated, HistoryEntryDtoExtensions.KnownEntityTypes.ApiScope);
        entry.Changes.Add(new FieldChangeDto("Enabled", "True", "False"));
        entry.EntityIdentifier = $"{currentApiResource.Name}.deleted-scope";

        // Act
        var result = _sut.CanUndo(entry, currentApiResource);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result.CanUndo, Is.False);
            Assert.That(result.Reason, Does.Contain("scope no longer exists"));
        }
    }

    [Test]
    public void CanUndo_WithUpdatedApiScope_WhenNoScopesOnApiResource_ReturnsIneligible()
    {
        // Arrange
        var currentApiResource = CreateTestApiResource();
        // No scopes added to the API resource

        var entry = CreateHistoryEntry(HistoryEventType.Updated, HistoryEntryDtoExtensions.KnownEntityTypes.ApiScope);
        entry.Changes.Add(new FieldChangeDto("Enabled", "True", "False"));
        entry.EntityIdentifier = $"{currentApiResource.Name}.test-scope";

        // Act
        var result = _sut.CanUndo(entry, currentApiResource);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result.CanUndo, Is.False);
            Assert.That(result.Reason, Does.Contain("scope no longer exists"));
        }
    }

    #endregion

    #region ExecuteUndoAsync - Update ApiResource Tests

    [Test]
    public async Task ExecuteUndoAsync_WithUpdatedApiResource_CallsUpdateApiResource()
    {
        // Arrange
        var entry = CreateHistoryEntry(HistoryEventType.Updated, HistoryEntryDtoExtensions.KnownEntityTypes.ApiResource);
        entry.Changes.Add(new FieldChangeDto("DisplayName", "NewDisplayName", "OldDisplayName"));
        entry.Changes.Add(new FieldChangeDto("Description", "NewDescription", "OldDescription"));
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
                dto.Description == "OldDescription" &&
                dto.Enabled == false));
        }
    }

    [Test]
    public async Task ExecuteUndoAsync_WithUpdatedApiResourcePartialFields_UpdatesOnlyProvidedFields()
    {
        // Arrange
        var entry = CreateHistoryEntry(HistoryEventType.Updated, HistoryEntryDtoExtensions.KnownEntityTypes.ApiResource);
        entry.Changes.Add(new FieldChangeDto("DisplayName", "NewDisplayName", "OldDisplayName"));

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
                dto.Description == null &&
                dto.Enabled == null));
        }
    }

    [Test]
    public async Task ExecuteUndoAsync_WithUpdatedApiResource_WhenApiCallFails_ReturnsError()
    {
        // Arrange
        var entry = CreateHistoryEntry(HistoryEventType.Updated, HistoryEntryDtoExtensions.KnownEntityTypes.ApiResource);
        entry.Changes.Add(new FieldChangeDto("DisplayName", "NewDisplayName", "OldDisplayName"));

        var currentApiResource = CreateTestApiResource();
        _mockAdminApiService.UpdateApiResource(Arg.Any<ApiResourceDtoUpdate>())
            .Returns(new ApiCallResult<ApiResourceDtoRead>("Update failed"));

        // Act
        var result = await _sut.ExecuteUndoAsync(entry, currentApiResource);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result.IsSuccess, Is.False);
            Assert.That(result.ErrorMessage, Does.Contain("Update failed"));
        }
    }

    #endregion

    #region ExecuteUndoAsync - Update ApiScope Tests

    [Test]
    public async Task ExecuteUndoAsync_WithUpdatedApiScope_CallsUpdateApiResourceScope()
    {
        // Arrange
        var currentApiResource = CreateTestApiResource();

        var scopeOwnName = "read";
        var fullyQualifiedScopeName = $"{currentApiResource.Name}.{scopeOwnName}";

        var expectedScopeResult = new ApiResourcePropertyScopeDtoRead { Id = 123, Scope = fullyQualifiedScopeName };
        currentApiResource.Scopes.Add(expectedScopeResult);

        var entry = CreateHistoryEntry(HistoryEntryDtoExtensions.KnownEntityTypes.ApiScope);
        entry.EntityIdentifier = fullyQualifiedScopeName;
        entry.Changes.Add(new FieldChangeDto("Enabled", "True", "False"));
        entry.Changes.Add(new FieldChangeDto("Required", "False", "True"));
        entry.Changes.Add(new FieldChangeDto("DisplayName", "NewDisplayName", "OldDisplayName"));
        entry.Changes.Add(new FieldChangeDto("Description", "NewDescription", "OldDescription"));

        var expectedApiResourceResult = CreateTestApiResource();

        _mockAdminApiService.UpdateApiResourceScope(Arg.Any<ApiResourcePropertyScopeDtoUpdate>())
            .Returns(new ApiCallResult<ApiResourcePropertyScopeDtoRead>(expectedScopeResult));
        _mockAdminApiService.GetApiResource(1)
            .Returns(new ApiCallResult<ApiResourceDtoRead>(expectedApiResourceResult));

        // Act
        var result = await _sut.ExecuteUndoAsync(entry, currentApiResource);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result.IsSuccess, Is.True);
            await _mockAdminApiService.Received(1).UpdateApiResourceScope(Arg.Is<ApiResourcePropertyScopeDtoUpdate>(dto =>
                dto.Id == 123 &&
                dto.Enabled == false &&
                dto.Required == true &&
                dto.DisplayName == "OldDisplayName" &&
                dto.Description == "OldDescription"));
            await _mockAdminApiService.Received(1).GetApiResource(1);
        }
    }

    [Test]
    public async Task ExecuteUndoAsync_WithUpdatedApiScope_WhenEntityIdCannotBeExtracted_ReturnsError()
    {
        // Arrange
        var entry = CreateHistoryEntry(HistoryEntryDtoExtensions.KnownEntityTypes.ApiScope);
        entry.EntityIdentifier = "invalid-identifier-without-id";
        entry.Changes.Add(new FieldChangeDto("Enabled", "True", "False"));

        var currentApiResource = CreateTestApiResource();

        // Act
        var result = await _sut.ExecuteUndoAsync(entry, currentApiResource);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result.IsSuccess, Is.False);
            Assert.That(result.ErrorMessage, Does.Contain("Cannot determine scope ID"));
        }
    }

    [Test]
    public async Task ExecuteUndoAsync_WithUpdatedApiScope_WhenUpdateFails_ReturnsError()
    {
        // Arrange
        var currentApiResource = CreateTestApiResource();

        var scopeOwnName = "read";
        var fullyQualifiedScopeName = $"{currentApiResource.Name}.{scopeOwnName}";

        currentApiResource.Scopes.Add(new ApiResourcePropertyScopeDtoRead { Id = 123, Scope = fullyQualifiedScopeName });

        var entry = CreateHistoryEntry(HistoryEntryDtoExtensions.KnownEntityTypes.ApiScope);
        entry.EntityIdentifier = fullyQualifiedScopeName;
        entry.Changes.Add(new FieldChangeDto("Enabled", "True", "False"));

        _mockAdminApiService.UpdateApiResourceScope(Arg.Any<ApiResourcePropertyScopeDtoUpdate>())
            .Returns(new ApiCallResult<ApiResourcePropertyScopeDtoRead>("Update failed"));

        // Act
        var result = await _sut.ExecuteUndoAsync(entry, currentApiResource);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result.IsSuccess, Is.False);
            Assert.That(result.ErrorMessage, Does.Contain("Update failed"));
        }
    }

    [Test]
    public async Task ExecuteUndoAsync_WithUpdatedApiScope_WhenFetchApiResourceFails_ReturnsError()
    {
        // Arrange
        var currentApiResource = CreateTestApiResource();
        var scopeOwnName = "read";
        var fullyQualifiedScopeName = $"{currentApiResource.Name}.{scopeOwnName}";

        var expectedScopeResult = new ApiResourcePropertyScopeDtoRead { Id = 123, Scope = fullyQualifiedScopeName };
        currentApiResource.Scopes.Add(expectedScopeResult);

        var entry = CreateHistoryEntry(HistoryEntryDtoExtensions.KnownEntityTypes.ApiScope);
        entry.EntityIdentifier = fullyQualifiedScopeName;
        entry.Changes.Add(new FieldChangeDto("Enabled", "True", "False"));

        _mockAdminApiService.UpdateApiResourceScope(Arg.Any<ApiResourcePropertyScopeDtoUpdate>())
            .Returns(new ApiCallResult<ApiResourcePropertyScopeDtoRead>(expectedScopeResult));
        _mockAdminApiService.GetApiResource(1)
            .Returns(new ApiCallResult<ApiResourceDtoRead>("Failed to fetch"));

        // Act
        var result = await _sut.ExecuteUndoAsync(entry, currentApiResource);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result.IsSuccess, Is.False);
            Assert.That(result.ErrorMessage, Does.Contain("Scope updated but failed to fetch updated API resource"));
        }
    }

    #endregion

    #region ExecuteUndoAsync - Delete (Recreate) ApiScope Tests

    [Test]
    public async Task ExecuteUndoAsync_WithDeletedApiScope_CallsAddApiResourceScope()
    {
        // Arrange
        var currentApiResource = CreateTestApiResource();

        var scopeOwnName = "read";
        var fullyQualifiedScopeName = $"{currentApiResource.Name}.{scopeOwnName}";

        var entry = CreateHistoryEntry(HistoryEventType.Deleted, HistoryEntryDtoExtensions.KnownEntityTypes.ApiScope);
        entry.Changes.Add(new FieldChangeDto("Name", null, fullyQualifiedScopeName));
        entry.Changes.Add(new FieldChangeDto("DisplayName", null, "API Read"));
        entry.Changes.Add(new FieldChangeDto("Description", null, "Read access"));
        entry.Changes.Add(new FieldChangeDto("Enabled", null, "True"));
        entry.Changes.Add(new FieldChangeDto("Required", null, "False"));

        var expectedScopeResult = new ApiResourcePropertyScopeDtoRead { Id = 1, Scope = fullyQualifiedScopeName };
        var expectedApiResourceResult = CreateTestApiResource();

        _mockAdminApiService.AddApiResourceScope(Arg.Any<ApiResourcePropertyScopeDtoCreate>())
            .Returns(new ApiCallResult<ApiResourcePropertyScopeDtoRead>(expectedScopeResult));
        _mockAdminApiService.GetApiResource(1)
            .Returns(new ApiCallResult<ApiResourceDtoRead>(expectedApiResourceResult));

        // Act
        var result = await _sut.ExecuteUndoAsync(entry, currentApiResource);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result.IsSuccess, Is.True);
            await _mockAdminApiService.Received(1).AddApiResourceScope(Arg.Is<ApiResourcePropertyScopeDtoCreate>(dto =>
                dto.ApiResourceId == 1 &&
                dto.Name == scopeOwnName &&
                dto.DisplayName == "API Read" &&
                dto.Description == "Read access" &&
                dto.Enabled == true &&
                dto.Required == false));
            await _mockAdminApiService.Received(1).GetApiResource(1);
        }
    }

    [Test]
    public async Task ExecuteUndoAsync_WithDeletedApiScope_UsingNameField_CallsAddApiResourceScope()
    {
        // Arrange
        var currentApiResource = CreateTestApiResource();

        var scopeOwnName = "write";
        var fullyQualifiedScopeName = $"{currentApiResource.Name}.{scopeOwnName}";

        var entry = CreateHistoryEntry(HistoryEventType.Deleted, HistoryEntryDtoExtensions.KnownEntityTypes.ApiScope);
        entry.Changes.Add(new FieldChangeDto("Name", null, fullyQualifiedScopeName));

        var expectedScopeResult = new ApiResourcePropertyScopeDtoRead { Id = 1, Scope = fullyQualifiedScopeName };
        var expectedApiResourceResult = CreateTestApiResource();

        _mockAdminApiService.AddApiResourceScope(Arg.Any<ApiResourcePropertyScopeDtoCreate>())
            .Returns(new ApiCallResult<ApiResourcePropertyScopeDtoRead>(expectedScopeResult));
        _mockAdminApiService.GetApiResource(1)
            .Returns(new ApiCallResult<ApiResourceDtoRead>(expectedApiResourceResult));

        // Act
        var result = await _sut.ExecuteUndoAsync(entry, currentApiResource);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result.IsSuccess, Is.True);
            await _mockAdminApiService.Received(1).AddApiResourceScope(Arg.Is<ApiResourcePropertyScopeDtoCreate>(dto =>
                dto.ApiResourceId == 1 &&
                dto.Name == scopeOwnName));
        }
    }

    [Test]
    public async Task ExecuteUndoAsync_WithDeletedApiScope_WhenMissingScopeName_ReturnsError()
    {
        // Arrange
        var entry = CreateHistoryEntry(HistoryEventType.Deleted, HistoryEntryDtoExtensions.KnownEntityTypes.ApiScope);
        // No Scope or Name change added

        var currentApiResource = CreateTestApiResource();

        // Act
        var result = await _sut.ExecuteUndoAsync(entry, currentApiResource);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result.IsSuccess, Is.False);
            Assert.That(result.ErrorMessage, Does.Contain("missing required scope name"));
        }
    }

    [Test]
    public async Task ExecuteUndoAsync_WithDeletedApiScope_WhenAddFails_ReturnsError()
    {
        // Arrange
        var currentApiResource = CreateTestApiResource();

        var scopeOwnName = "read";
        var fullyQualifiedScopeName = $"{currentApiResource.Name}.{scopeOwnName}";

        var entry = CreateHistoryEntry(HistoryEventType.Deleted, HistoryEntryDtoExtensions.KnownEntityTypes.ApiScope);
        entry.Changes.Add(new FieldChangeDto("Name", null, fullyQualifiedScopeName));

        _mockAdminApiService.AddApiResourceScope(Arg.Any<ApiResourcePropertyScopeDtoCreate>())
            .Returns(new ApiCallResult<ApiResourcePropertyScopeDtoRead>("Add failed"));

        // Act
        var result = await _sut.ExecuteUndoAsync(entry, currentApiResource);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result.IsSuccess, Is.False);
            Assert.That(result.ErrorMessage, Does.Contain("Add failed"));
        }
    }

    [Test]
    public async Task ExecuteUndoAsync_WithDeletedApiScope_WhenApiResourceNameIsEmpty_ReturnsError()
    {
        // Arrange
        var currentApiResource = CreateTestApiResource();
        currentApiResource.Name = string.Empty; // Empty API resource name

        var entry = CreateHistoryEntry(HistoryEventType.Deleted, HistoryEntryDtoExtensions.KnownEntityTypes.ApiScope);
        entry.Changes.Add(new FieldChangeDto("Name", null, "test-api.read"));

        // Act
        var result = await _sut.ExecuteUndoAsync(entry, currentApiResource);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result.IsSuccess, Is.False);
            Assert.That(result.ErrorMessage, Does.Contain("API resource name is missing"));
        }
    }

    [Test]
    public async Task ExecuteUndoAsync_WithDeletedApiScope_WhenApiResourceNameIsNull_ReturnsError()
    {
        // Arrange
        var currentApiResource = CreateTestApiResource();
        currentApiResource.Name = null!; // Null API resource name

        var entry = CreateHistoryEntry(HistoryEventType.Deleted, HistoryEntryDtoExtensions.KnownEntityTypes.ApiScope);
        entry.Changes.Add(new FieldChangeDto("Name", null, "test-api.read"));

        // Act
        var result = await _sut.ExecuteUndoAsync(entry, currentApiResource);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result.IsSuccess, Is.False);
            Assert.That(result.ErrorMessage, Does.Contain("API resource name is missing"));
        }
    }

    [Test]
    public async Task ExecuteUndoAsync_WithDeletedApiScope_WhenScopeNameDoesNotMatchExpectedFormat_ReturnsError()
    {
        // Arrange
        var currentApiResource = CreateTestApiResource();
        currentApiResource.Name = "test-api";

        var entry = CreateHistoryEntry(HistoryEventType.Deleted, HistoryEntryDtoExtensions.KnownEntityTypes.ApiScope);
        entry.Changes.Add(new FieldChangeDto("Name", null, "different-api.read")); // Doesn't start with "test-api."

        // Act
        var result = await _sut.ExecuteUndoAsync(entry, currentApiResource);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result.IsSuccess, Is.False);
            Assert.That(result.ErrorMessage, Does.Contain("scope name does not match expected format"));
        }
    }

    [Test]
    public async Task ExecuteUndoAsync_WithDeletedApiScope_WhenScopeNameHasNoDotPrefix_ReturnsError()
    {
        // Arrange
        var currentApiResource = CreateTestApiResource();
        currentApiResource.Name = "test-api";

        var entry = CreateHistoryEntry(HistoryEventType.Deleted, HistoryEntryDtoExtensions.KnownEntityTypes.ApiScope);
        entry.Changes.Add(new FieldChangeDto("Name", null, "test-apiread")); // Missing dot after api name

        // Act
        var result = await _sut.ExecuteUndoAsync(entry, currentApiResource);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result.IsSuccess, Is.False);
            Assert.That(result.ErrorMessage, Does.Contain("scope name does not match expected format"));
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
    public async Task ExecuteUndoAsync_WithDeletedApiResourceRole_WhenMissingRoleName_ReturnsError()
    {
        // Arrange
        var entry = CreateHistoryEntry(HistoryEventType.Deleted, HistoryEntryDtoExtensions.KnownEntityTypes.ApiResourceRole);
        // No RoleName change added

        var currentApiResource = CreateTestApiResource();

        // Act
        var result = await _sut.ExecuteUndoAsync(entry, currentApiResource);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result.IsSuccess, Is.False);
            Assert.That(result.ErrorMessage, Does.Contain("missing required RoleName"));
        }
    }

    [Test]
    public async Task ExecuteUndoAsync_WithDeletedApiResourceRole_WhenAddFails_ReturnsError()
    {
        // Arrange
        var entry = CreateHistoryEntry(HistoryEventType.Deleted, HistoryEntryDtoExtensions.KnownEntityTypes.ApiResourceRole);
        entry.Changes.Add(new FieldChangeDto("RoleName", null, "admin"));

        var currentApiResource = CreateTestApiResource();
        _mockAdminApiService.AddApiResourceRole(Arg.Any<ApiResourcePropertyRoleDtoCreate>())
            .Returns(new ApiCallResult<ApiResourcePropertyRoleDtoRead>("Add failed"));

        // Act
        var result = await _sut.ExecuteUndoAsync(entry, currentApiResource);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result.IsSuccess, Is.False);
            Assert.That(result.ErrorMessage, Does.Contain("Add failed"));
        }
    }

    #endregion

    #region ExecuteUndoAsync - Delete (Recreate) ApiResourceRoleMapping Tests

    [Test]
    public async Task ExecuteUndoAsync_WithDeletedApiResourceRoleMapping_CallsAddApiResourceRoleMapping()
    {
        // Arrange
        var entry = CreateHistoryEntry(HistoryEventType.Deleted, HistoryEntryDtoExtensions.KnownEntityTypes.ApiResourceRoleMapping, GetRoleMappingEntityIdentifier("admin", "test-group-id"));
        entry.Changes.Add(new FieldChangeDto("Value", null, "test-group-id"));
        entry.Changes.Add(new FieldChangeDto("MappingType", null, "SecurityGroup"));

        var currentApiResource = CreateTestApiResource();
        var existingRole1 = new ApiResourcePropertyRoleDtoRead
        {
            Id = 456,
            ApiResourceId = 1,
            RoleName = "admin",
        };
        currentApiResource.Roles.Add(existingRole1);
        var expectedMappingResult = new ApiResourcePropertyRoleMappingDtoRead
        {
            Id = 1,
            ApiResourceRoleId = 456,
            Value = "test-group-id",
            MappingType = RoleMapType.SecurityGroup
        };
        var expectedApiResourceResult = CreateTestApiResource();

        _mockAdminApiService.AddApiResourceRoleMapping(Arg.Any<ApiResourcePropertyRoleMappingDtoCreate>())
            .Returns(new ApiCallResult<ApiResourcePropertyRoleMappingDtoRead>(expectedMappingResult));
        _mockAdminApiService.GetApiResource(1)
            .Returns(new ApiCallResult<ApiResourceDtoRead>(expectedApiResourceResult));

        // Act
        var result = await _sut.ExecuteUndoAsync(entry, currentApiResource);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result.IsSuccess, Is.True);
            await _mockAdminApiService.Received(1).AddApiResourceRoleMapping(Arg.Is<ApiResourcePropertyRoleMappingDtoCreate>(dto =>
                dto.ApiResourceRoleId == 456 &&
                dto.Value == "test-group-id" &&
                dto.MappingType == RoleMapType.SecurityGroup));
            await _mockAdminApiService.Received(1).GetApiResource(1);
        }
    }

    [Test]
    public async Task ExecuteUndoAsync_WithDeletedApiResourceRoleMapping_WhenMissingRoleId_ReturnsError()
    {
        // Arrange
        var entry = CreateHistoryEntry(HistoryEventType.Deleted, HistoryEntryDtoExtensions.KnownEntityTypes.ApiResourceRoleMapping);
        entry.EntityIdentifier = null;
        entry.Changes.Add(new FieldChangeDto("Value", null, "test-value"));
        entry.Changes.Add(new FieldChangeDto("MappingType", null, "SecurityGroup"));

        var currentApiResource = CreateTestApiResource();

        // Act
        var result = await _sut.ExecuteUndoAsync(entry, currentApiResource);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result.IsSuccess, Is.False);
            Assert.That(result.ErrorMessage, Does.Contain("Cannot determine role ID"));
        }
    }

    [Test]
    public async Task ExecuteUndoAsync_WithDeletedApiResourceRoleMapping_WhenMissingValue_ReturnsError()
    {
        // Arrange
        var entry = CreateHistoryEntry(HistoryEventType.Deleted, HistoryEntryDtoExtensions.KnownEntityTypes.ApiResourceRoleMapping, GetRoleMappingEntityIdentifier("admin", "test-group-id"));
        entry.Changes.Add(new FieldChangeDto("MappingType", null, "SecurityGroup"));

        var currentApiResource = CreateTestApiResource();
        var existingRole1 = new ApiResourcePropertyRoleDtoRead
        {
            Id = 1,
            ApiResourceId = 1,
            RoleName = "admin",
        };
        currentApiResource.Roles.Add(existingRole1);

        // Act
        var result = await _sut.ExecuteUndoAsync(entry, currentApiResource);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result.IsSuccess, Is.False);
            Assert.That(result.ErrorMessage, Does.Contain("missing required Value"));
        }
    }

    [Test]
    public async Task ExecuteUndoAsync_WithDeletedApiResourceRoleMapping_WhenMissingMappingType_ReturnsError()
    {
        // Arrange
        var entry = CreateHistoryEntry(HistoryEventType.Deleted, HistoryEntryDtoExtensions.KnownEntityTypes.ApiResourceRoleMapping, GetRoleMappingEntityIdentifier("admin", "test-group-id"));
        entry.Changes.Add(new FieldChangeDto("Value", null, "test-value"));

        var currentApiResource = CreateTestApiResource();
        var existingRole1 = new ApiResourcePropertyRoleDtoRead
        {
            Id = 1,
            ApiResourceId = 1,
            RoleName = "admin",
        };
        currentApiResource.Roles.Add(existingRole1);

        // Act
        var result = await _sut.ExecuteUndoAsync(entry, currentApiResource);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result.IsSuccess, Is.False);
            Assert.That(result.ErrorMessage, Does.Contain("missing or invalid MappingType"));
        }
    }

    [Test]
    public async Task ExecuteUndoAsync_WithDeletedApiResourceRoleMapping_WhenInvalidMappingType_ReturnsError()
    {
        // Arrange
        var entry = CreateHistoryEntry(HistoryEventType.Deleted, HistoryEntryDtoExtensions.KnownEntityTypes.ApiResourceRoleMapping, GetRoleMappingEntityIdentifier("admin", "test-group-id"));
        entry.Changes.Add(new FieldChangeDto("Value", null, "test-value"));
        entry.Changes.Add(new FieldChangeDto("MappingType", null, "InvalidMappingType"));

        var currentApiResource = CreateTestApiResource();
        var existingRole1 = new ApiResourcePropertyRoleDtoRead
        {
            Id = 1,
            ApiResourceId = 1,
            RoleName = "admin",
        };
        currentApiResource.Roles.Add(existingRole1);

        // Act
        var result = await _sut.ExecuteUndoAsync(entry, currentApiResource);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result.IsSuccess, Is.False);
            Assert.That(result.ErrorMessage, Does.Contain("missing or invalid MappingType"));
        }
    }

    [Test]
    public async Task ExecuteUndoAsync_WithDeletedApiResourceRoleMapping_WhenAddFails_ReturnsError()
    {
        // Arrange
        var entry = CreateHistoryEntry(HistoryEventType.Deleted, HistoryEntryDtoExtensions.KnownEntityTypes.ApiResourceRoleMapping, GetRoleMappingEntityIdentifier("admin", "test-group-id"));
        entry.Changes.Add(new FieldChangeDto("Value", null, "test-value"));
        entry.Changes.Add(new FieldChangeDto("MappingType", null, "SecurityGroup"));

        var currentApiResource = CreateTestApiResource();
        var existingRole1 = new ApiResourcePropertyRoleDtoRead
        {
            Id = 1,
            ApiResourceId = 1,
            RoleName = "admin",
        };
        currentApiResource.Roles.Add(existingRole1);
        _mockAdminApiService.AddApiResourceRoleMapping(Arg.Any<ApiResourcePropertyRoleMappingDtoCreate>())
            .Returns(new ApiCallResult<ApiResourcePropertyRoleMappingDtoRead>("Add failed"));

        // Act
        var result = await _sut.ExecuteUndoAsync(entry, currentApiResource);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result.IsSuccess, Is.False);
            Assert.That(result.ErrorMessage, Does.Contain("Add failed"));
        }
    }

    [Test]
    public async Task ExecuteUndoAsync_WithDeletedApiResourceRoleMapping_WhenRoleIdFromEntityIdentifier_CallsAddApiResourceRoleMapping()
    {
        // Arrange
        var entry = CreateHistoryEntry(HistoryEventType.Deleted, HistoryEntryDtoExtensions.KnownEntityTypes.ApiResourceRoleMapping, GetRoleMappingEntityIdentifier("TestRole", "test-group-id"));
        entry.Changes.Add(new FieldChangeDto("Value", null, "test-group-id"));
        entry.Changes.Add(new FieldChangeDto("MappingType", null, "SecurityGroup"));

        var currentApiResource = CreateTestApiResource();
        currentApiResource.Roles.Add(new ApiResourcePropertyRoleDtoRead
        {
            Id = 123,
            ApiResourceId = 1,
            RoleName = "TestRole",
            Mappings = new List<ApiResourcePropertyRoleMappingDtoRead>()
        });

        var expectedMappingResult = new ApiResourcePropertyRoleMappingDtoRead
        {
            Id = 1,
            ApiResourceRoleId = 123,
            Value = "test-group-id",
            MappingType = RoleMapType.SecurityGroup
        };
        var expectedApiResourceResult = CreateTestApiResource();

        _mockAdminApiService.AddApiResourceRoleMapping(Arg.Any<ApiResourcePropertyRoleMappingDtoCreate>())
            .Returns(new ApiCallResult<ApiResourcePropertyRoleMappingDtoRead>(expectedMappingResult));
        _mockAdminApiService.GetApiResource(1)
            .Returns(new ApiCallResult<ApiResourceDtoRead>(expectedApiResourceResult));

        // Act
        var result = await _sut.ExecuteUndoAsync(entry, currentApiResource);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result.IsSuccess, Is.True);
            await _mockAdminApiService.Received(1).AddApiResourceRoleMapping(Arg.Is<ApiResourcePropertyRoleMappingDtoCreate>(dto =>
                dto.ApiResourceRoleId == 123 &&
                dto.Value == "test-group-id" &&
                dto.MappingType == RoleMapType.SecurityGroup));
            await _mockAdminApiService.Received(1).GetApiResource(1);
        }
    }

    [Test]
    public async Task ExecuteUndoAsync_WithDeletedApiResourceRoleMapping_WhenRoleNotFoundInEntity_ReturnsError()
    {
        // Arrange
        var entry = CreateHistoryEntry(HistoryEventType.Deleted, HistoryEntryDtoExtensions.KnownEntityTypes.ApiResourceRoleMapping, GetRoleMappingEntityIdentifier("NonExistentRole", "test-group-id"));
        entry.Changes.Add(new FieldChangeDto("Value", null, "test-group-id"));
        entry.Changes.Add(new FieldChangeDto("MappingType", null, "SecurityGroup"));

        var currentApiResource = CreateTestApiResource();
        currentApiResource.Roles.Add(new ApiResourcePropertyRoleDtoRead
        {
            Id = 123,
            ApiResourceId = 1,
            RoleName = "DifferentRole",
            Mappings = new List<ApiResourcePropertyRoleMappingDtoRead>()
        });

        // Act
        var result = await _sut.ExecuteUndoAsync(entry, currentApiResource);

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
        var entry = CreateHistoryEntry(HistoryEventType.Created, HistoryEntryDtoExtensions.KnownEntityTypes.ApiResource);

        var currentApiResource = CreateTestApiResource();

        // Act
        var result = await _sut.ExecuteUndoAsync(entry, currentApiResource);

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
        var entry = CreateHistoryEntry(HistoryEventType.Updated, HistoryEntryDtoExtensions.KnownEntityTypes.ApiResourceRole);
        entry.Changes.Add(new FieldChangeDto("RoleName", "NewName", "OldName"));

        var currentApiResource = CreateTestApiResource();

        // Act
        var result = await _sut.ExecuteUndoAsync(entry, currentApiResource);

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

    /// <summary>
    /// Creates a history entry for an Updated event (convenience overload for update tests).
    /// </summary>
    private static HistoryEntryDto CreateHistoryEntry(string entityType)
    {
        return CreateHistoryEntry(HistoryEventType.Updated, entityType);
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

    #endregion
}
