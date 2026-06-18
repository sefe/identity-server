#nullable enable

using NSubstitute;
using IdentityServer.Abstraction.DTO.History;
using IdentityServer.Abstraction.DTO.SystemPermissions;
using IdentityServer.Abstraction.Enums;
using IdentityServer.AdminPortal.Web.Services;
using IdentityServer.AdminPortal.Web.Services.History;

namespace IdentityServer.AdminPortal.Web.Tests.Services.History;

[TestFixture]
public class SystemPermissionHistoryUndoServiceTests
{
    private IAdminApiService _mockAdminApiService = null!;
    private SystemPermissionHistoryUndoService _sut = null!;

    [SetUp]
    public void Setup()
    {
        _mockAdminApiService = Substitute.For<IAdminApiService>();
        _sut = new SystemPermissionHistoryUndoService(_mockAdminApiService);
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
            Assert.That(supportedTypes, Does.Contain(HistoryEntryDtoExtensions.KnownEntityTypes.SystemPermission));
            Assert.That(supportedTypes, Does.Contain(HistoryEntryDtoExtensions.KnownEntityTypes.SystemPermissionEnvironment));
            Assert.That(supportedTypes, Does.Contain(HistoryEntryDtoExtensions.KnownEntityTypes.SystemPermissionRole));
            Assert.That(supportedTypes, Has.Count.EqualTo(3));
        }
    }

    #endregion

    #region CanHandle Tests

    [TestCase(HistoryEntryDtoExtensions.KnownEntityTypes.SystemPermission, true)]
    [TestCase(HistoryEntryDtoExtensions.KnownEntityTypes.SystemPermissionEnvironment, true)]
    [TestCase(HistoryEntryDtoExtensions.KnownEntityTypes.Client, false)]
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
            Assert.That(_sut.CanHandle("systempermission"), Is.True);
            Assert.That(_sut.CanHandle("SYSTEMPERMISSION"), Is.True);
            Assert.That(_sut.CanHandle("SystemPermission"), Is.True);
            Assert.That(_sut.CanHandle("systempermissionenvironment"), Is.True);
            Assert.That(_sut.CanHandle("SYSTEMPERMISSIONENVIRONMENT"), Is.True);
        }
    }

    #endregion

    #region CanUndo - Base Eligibility Tests

    [Test]
    public void CanUndo_WithCreatedEvent_ReturnsIneligible()
    {
        // Arrange
        var entry = CreateHistoryEntry(HistoryEventType.Created, HistoryEntryDtoExtensions.KnownEntityTypes.SystemPermissionEnvironment);
        var currentSystemPermission = CreateTestSystemPermission();

        // Act
        var result = _sut.CanUndo(entry, currentSystemPermission);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result.CanUndo, Is.False);
            Assert.That(result.Reason, Does.Contain("Created events cannot be undone"));
        }
    }

    [Test]
    public void CanUndo_WithDeletedSystemPermissionParentEntity_ReturnsIneligible()
    {
        // Arrange
        var entry = CreateHistoryEntry(HistoryEventType.Deleted, HistoryEntryDtoExtensions.KnownEntityTypes.SystemPermission);
        var currentSystemPermission = CreateTestSystemPermission();

        // Act
        var result = _sut.CanUndo(entry, currentSystemPermission);

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
        var entry = CreateHistoryEntry(HistoryEventType.Updated, HistoryEntryDtoExtensions.KnownEntityTypes.SystemPermission);
        entry.Changes.Add(new FieldChangeDto("Description", "NewDescription", "OldDescription"));

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
    public void CanUndo_WithDeletedEnvironment_WhenNoConflict_ReturnsEligible()
    {
        // Arrange
        var entry = CreateHistoryEntry(HistoryEventType.Deleted, HistoryEntryDtoExtensions.KnownEntityTypes.SystemPermissionEnvironment);
        entry.Changes.Add(new FieldChangeDto("Environment", null, "DEV"));

        var currentSystemPermission = CreateTestSystemPermission();
        currentSystemPermission.Environments.Add(new SystemPermissionEnvironmentDtoRead
        {
            Id = 1,
            Environment = "UAT",
            SystemPermissionId = 1
        });

        // Act
        var result = _sut.CanUndo(entry, currentSystemPermission);

        // Assert
        Assert.That(result.CanUndo, Is.True);
    }

    [Test]
    public void CanUndo_WithDeletedEnvironment_WhenDuplicateExists_ReturnsIneligible()
    {
        // Arrange
        var entry = CreateHistoryEntry(HistoryEventType.Deleted, HistoryEntryDtoExtensions.KnownEntityTypes.SystemPermissionEnvironment);
        entry.Changes.Add(new FieldChangeDto("Environment", null, "DEV"));

        var currentSystemPermission = CreateTestSystemPermission();
        currentSystemPermission.Environments.Add(new SystemPermissionEnvironmentDtoRead
        {
            Id = 1,
            Environment = "DEV",
            SystemPermissionId = 1
        });

        // Act
        var result = _sut.CanUndo(entry, currentSystemPermission);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result.CanUndo, Is.False);
            Assert.That(result.Reason, Does.Contain("environment with this name already exists"));
        }
    }

    [Test]
    public void CanUndo_WithDeletedEnvironment_WhenDuplicateExistsCaseInsensitive_ReturnsIneligible()
    {
        // Arrange
        var entry = CreateHistoryEntry(HistoryEventType.Deleted, HistoryEntryDtoExtensions.KnownEntityTypes.SystemPermissionEnvironment);
        entry.Changes.Add(new FieldChangeDto("Environment", null, "dev"));

        var currentSystemPermission = CreateTestSystemPermission();
        currentSystemPermission.Environments.Add(new SystemPermissionEnvironmentDtoRead
        {
            Id = 1,
            Environment = "DEV",
            SystemPermissionId = 1
        });

        // Act
        var result = _sut.CanUndo(entry, currentSystemPermission);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result.CanUndo, Is.False);
            Assert.That(result.Reason, Does.Contain("environment with this name already exists"));
        }
    }

    [Test]
    public void CanUndo_WithUpdatedSystemPermission_ReturnsEligible()
    {
        // Arrange
        var entry = CreateHistoryEntry(HistoryEventType.Updated, HistoryEntryDtoExtensions.KnownEntityTypes.SystemPermission);
        entry.Changes.Add(new FieldChangeDto("Description", "NewDescription", "OldDescription"));

        var currentSystemPermission = CreateTestSystemPermission();

        // Act
        var result = _sut.CanUndo(entry, currentSystemPermission);

        // Assert
        Assert.That(result.CanUndo, Is.True);
    }

    [Test]
    public void CanUndo_WithUpdatedSystemPermissionEnvironment_ReturnsIneligible()
    {
        // Arrange
        var entry = CreateHistoryEntry(HistoryEventType.Updated, HistoryEntryDtoExtensions.KnownEntityTypes.SystemPermissionEnvironment);
        entry.Changes.Add(new FieldChangeDto("Environment", "NewEnv", "OldEnv"));

        var currentSystemPermission = CreateTestSystemPermission();

        // Act
        var result = _sut.CanUndo(entry, currentSystemPermission);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result.CanUndo, Is.False);
            Assert.That(result.Reason, Does.Contain("Cannot undo Update for entity SystemPermissionEnvironment"));
        }
    }

    [Test]
    public void CanUndo_WithUpdatedSystemPermissionRole_ReturnsIneligible()
    {
        // Arrange
        var entry = CreateHistoryEntry(HistoryEventType.Updated, HistoryEntryDtoExtensions.KnownEntityTypes.SystemPermissionRole);
        entry.Changes.Add(new FieldChangeDto("RoleType", "Writer", "Reader"));

        var currentSystemPermission = CreateTestSystemPermission();

        // Act
        var result = _sut.CanUndo(entry, currentSystemPermission);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result.CanUndo, Is.False);
            Assert.That(result.Reason, Does.Contain("Cannot undo Update for entity SystemPermissionRole"));
        }
    }

    #endregion

    #region ExecuteUndoAsync - Update Operations Tests

    [Test]
    public async Task ExecuteUndoAsync_WithSystemPermissionUpdate_CallsUpdateSystemPermission()
    {
        // Arrange
        var entry = CreateHistoryEntry(HistoryEventType.Updated, HistoryEntryDtoExtensions.KnownEntityTypes.SystemPermission);
        entry.Changes.Add(new FieldChangeDto("Description", "NewDescription", "OldDescription"));

        var currentSystemPermission = CreateTestSystemPermission();
        currentSystemPermission.Id = 42;

        var updatedSystemPermission = CreateTestSystemPermission();
        updatedSystemPermission.Description = "OldDescription";

        _mockAdminApiService.UpdateSystemPermission(Arg.Any<SystemPermissionDtoUpdate>())
            .Returns(ApiCallResult<SystemPermissionDtoRead>.Success(updatedSystemPermission));

        // Act
        var result = await _sut.ExecuteUndoAsync(entry, currentSystemPermission);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result.IsSuccess, Is.True);
            Assert.That(result.Result, Is.Not.Null);
            Assert.That(result.Result!.Description, Is.EqualTo("OldDescription"));
        }

        await _mockAdminApiService.Received(1).UpdateSystemPermission(
            Arg.Is<SystemPermissionDtoUpdate>(dto =>
                dto.Id == 42 &&
                dto.Description == "OldDescription"));
    }

    [Test]
    public async Task ExecuteUndoAsync_WithSystemPermissionUpdate_WhenMissingDescription_ReturnsError()
    {
        // Arrange
        var entry = CreateHistoryEntry(HistoryEventType.Updated, HistoryEntryDtoExtensions.KnownEntityTypes.SystemPermission);
        entry.Changes.Add(new FieldChangeDto("Name", "NewName", "OldName"));

        var currentSystemPermission = CreateTestSystemPermission();

        // Act
        var result = await _sut.ExecuteUndoAsync(entry, currentSystemPermission);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result.IsSuccess, Is.False);
            Assert.That(result.ErrorMessage, Does.Contain("missing required Description"));
        }

        await _mockAdminApiService.DidNotReceive().UpdateSystemPermission(Arg.Any<SystemPermissionDtoUpdate>());
    }

    [Test]
    public async Task ExecuteUndoAsync_WithSystemPermissionUpdate_WhenApiFails_ReturnsError()
    {
        // Arrange
        var entry = CreateHistoryEntry(HistoryEventType.Updated, HistoryEntryDtoExtensions.KnownEntityTypes.SystemPermission);
        entry.Changes.Add(new FieldChangeDto("Description", "NewDescription", "OldDescription"));

        var currentSystemPermission = CreateTestSystemPermission();

        _mockAdminApiService.UpdateSystemPermission(Arg.Any<SystemPermissionDtoUpdate>())
            .Returns(ApiCallResult<SystemPermissionDtoRead>.Error("API error occurred"));

        // Act
        var result = await _sut.ExecuteUndoAsync(entry, currentSystemPermission);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result.IsSuccess, Is.False);
            Assert.That(result.ErrorMessage, Does.Contain("API error occurred"));
        }
    }

    #endregion

    #region ExecuteUndoAsync - Delete Operations Tests

    [Test]
    public async Task ExecuteUndoAsync_WithDeletedEnvironment_RecreatesEnvironmentAndFetchesUpdatedSystemPermission()
    {
        // Arrange
        var entry = CreateHistoryEntry(HistoryEventType.Deleted, HistoryEntryDtoExtensions.KnownEntityTypes.SystemPermissionEnvironment);
        entry.Changes.Add(new FieldChangeDto("Environment", null, "PROD"));

        var currentSystemPermission = CreateTestSystemPermission();
        currentSystemPermission.Id = 10;

        var createdEnvironment = new SystemPermissionEnvironmentDtoRead
        {
            Id = 5,
            Environment = "PROD",
            SystemPermissionId = 10
        };

        var updatedSystemPermission = CreateTestSystemPermission();
        updatedSystemPermission.Id = 10;
        updatedSystemPermission.Environments.Add(createdEnvironment);

        _mockAdminApiService.CreateSystemPermissionEnvironment(Arg.Any<SystemPermissionEnvironmentDtoCreate>())
            .Returns(Task.FromResult(ApiCallResult<SystemPermissionDtoRead>.Success(updatedSystemPermission)));

        _mockAdminApiService.GetSystemPermission(10)
            .Returns(Task.FromResult(ApiCallResult<SystemPermissionDtoRead>.Success(updatedSystemPermission)));

        // Act
        var result = await _sut.ExecuteUndoAsync(entry, currentSystemPermission);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result.IsSuccess, Is.True);
            Assert.That(result.Result, Is.Not.Null);
            Assert.That(result.Result!.Environments, Has.Count.EqualTo(1));
            Assert.That(result.Result.Environments[0].Environment, Is.EqualTo("PROD"));
        }

        await _mockAdminApiService.Received(1).CreateSystemPermissionEnvironment(
            Arg.Is<SystemPermissionEnvironmentDtoCreate>(dto =>
                dto.SystemPermissionId == 10 &&
                dto.Environment == "PROD"));

        await _mockAdminApiService.Received(1).GetSystemPermission(10);
    }

    [Test]
    public async Task ExecuteUndoAsync_WithDeletedEnvironment_WhenMissingEnvironmentValue_ReturnsError()
    {
        // Arrange
        var entry = CreateHistoryEntry(HistoryEventType.Deleted, HistoryEntryDtoExtensions.KnownEntityTypes.SystemPermissionEnvironment);
        entry.Changes.Add(new FieldChangeDto("SystemPermissionId", null, "1"));

        var currentSystemPermission = CreateTestSystemPermission();

        // Act
        var result = await _sut.ExecuteUndoAsync(entry, currentSystemPermission);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result.IsSuccess, Is.False);
            Assert.That(result.ErrorMessage, Does.Contain("missing required Environment"));
        }

        await _mockAdminApiService.DidNotReceive().CreateSystemPermissionEnvironment(Arg.Any<SystemPermissionEnvironmentDtoCreate>());
    }

    [Test]
    public async Task ExecuteUndoAsync_WithDeletedEnvironment_WhenApiFailsToCreate_ReturnsError()
    {
        // Arrange
        var entry = CreateHistoryEntry(HistoryEventType.Deleted, HistoryEntryDtoExtensions.KnownEntityTypes.SystemPermissionEnvironment);
        entry.Changes.Add(new FieldChangeDto("Environment", null, "PROD"));

        var currentSystemPermission = CreateTestSystemPermission();

        _mockAdminApiService.CreateSystemPermissionEnvironment(Arg.Any<SystemPermissionEnvironmentDtoCreate>())
            .Returns(Task.FromResult(ApiCallResult<SystemPermissionDtoRead>.Error("Failed to create environment")));

        // Act
        var result = await _sut.ExecuteUndoAsync(entry, currentSystemPermission);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result.IsSuccess, Is.False);
            Assert.That(result.ErrorMessage, Does.Contain("Failed to create environment"));
        }

        await _mockAdminApiService.DidNotReceive().GetSystemPermission(Arg.Any<int>());
    }

    [Test]
    public async Task ExecuteUndoAsync_WithDeletedEnvironment_WhenGetSystemPermissionFails_ReturnsError()
    {
        // Arrange
        var entry = CreateHistoryEntry(HistoryEventType.Deleted, HistoryEntryDtoExtensions.KnownEntityTypes.SystemPermissionEnvironment);
        entry.Changes.Add(new FieldChangeDto("Environment", null, "PROD"));

        var currentSystemPermission = CreateTestSystemPermission();

        var createdEnvironment = new SystemPermissionEnvironmentDtoRead
        {
            Id = 5,
            Environment = "PROD",
            SystemPermissionId = 1
        };

        var recreatedSystemPermission = CreateTestSystemPermission();
        recreatedSystemPermission.Environments.Add(createdEnvironment);

        _mockAdminApiService.CreateSystemPermissionEnvironment(Arg.Any<SystemPermissionEnvironmentDtoCreate>())
            .Returns(Task.FromResult(ApiCallResult<SystemPermissionDtoRead>.Success(recreatedSystemPermission)));

        _mockAdminApiService.GetSystemPermission(1)
            .Returns(Task.FromResult(ApiCallResult<SystemPermissionDtoRead>.Error("Failed to fetch updated system permission")));

        // Act
        var result = await _sut.ExecuteUndoAsync(entry, currentSystemPermission);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result.IsSuccess, Is.False);
            Assert.That(result.ErrorMessage, Does.Contain("Child entity recreated but failed to fetch"));
        }
    }

    [Test]
    public async Task ExecuteUndoAsync_WithDeletedRole_RecreatesRoleAndFetchesUpdatedSystemPermission()
    {
        // Arrange
        var userName = "Test User";
        var envName = "Production";
        var entry = CreateHistoryEntry(HistoryEventType.Deleted, HistoryEntryDtoExtensions.KnownEntityTypes.SystemPermissionRole, GetRoleEntityIdentifier(envName, userName));
        entry.Changes.Add(new FieldChangeDto("User ID", null, "user-oid-123"));
        entry.Changes.Add(new FieldChangeDto("RoleType", null, "Reader"));

        var currentSystemPermission = CreateTestSystemPermission();
        currentSystemPermission.Environments.Add(new SystemPermissionEnvironmentDtoRead
        {
            Id = 3,
            Environment = envName,
            SystemPermissionId = currentSystemPermission.Id
        });

        var createdRole = new SystemPermissionRoleDtoRead
        {
            Id = 7,
            SystemPermissionEnvironmentId = 3,
            OId = "user-oid-123",
            Name = userName,
        };

        var updatedSystemPermission = CreateTestSystemPermission();
        updatedSystemPermission.Id = currentSystemPermission.Id;

        _mockAdminApiService.CreateSystemPermissionRole(Arg.Any<SystemPermissionRoleDtoCreate>())
            .Returns(Task.FromResult(ApiCallResult<SystemPermissionRoleDtoRead>.Success(createdRole)));

        _mockAdminApiService.GetSystemPermission(currentSystemPermission.Id)
            .Returns(Task.FromResult(ApiCallResult<SystemPermissionDtoRead>.Success(updatedSystemPermission)));

        // Act
        var result = await _sut.ExecuteUndoAsync(entry, currentSystemPermission);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result.IsSuccess, Is.True);
            Assert.That(result.Result, Is.Not.Null);
        }

        await _mockAdminApiService.Received(1).CreateSystemPermissionRole(
            Arg.Is<SystemPermissionRoleDtoCreate>(dto =>
                dto.SystemPermissionEnvironmentId == 3 &&
                dto.OId == "user-oid-123" &&
                dto.RoleType == Abstraction.Entities.IdentityServerConfig.SystemPermissions.SystemPermissionRoleType.Reader));

        await _mockAdminApiService.Received(1).GetSystemPermission(currentSystemPermission.Id);
    }

    [Test]
    public async Task ExecuteUndoAsync_WithDeletedRole_WhenMissingOId_ReturnsError()
    {
        // Arrange
        var userName = "Test User";
        var envName = "Production";
        var entry = CreateHistoryEntry(HistoryEventType.Deleted, HistoryEntryDtoExtensions.KnownEntityTypes.SystemPermissionRole, GetRoleEntityIdentifier(envName, userName));
        entry.Changes.Add(new FieldChangeDto("RoleType", null, "Reader"));

        var currentSystemPermission = CreateTestSystemPermission();
        currentSystemPermission.Environments.Add(new SystemPermissionEnvironmentDtoRead
        {
            Id = 3,
            Environment = envName,
            SystemPermissionId = currentSystemPermission.Id
        });

        // Act
        var result = await _sut.ExecuteUndoAsync(entry, currentSystemPermission);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result.IsSuccess, Is.False);
            Assert.That(result.ErrorMessage, Does.Contain("missing required User ID"));
        }

        await _mockAdminApiService.DidNotReceive().CreateSystemPermissionRole(Arg.Any<SystemPermissionRoleDtoCreate>());
    }

    [Test]
    public async Task ExecuteUndoAsync_WithDeletedRole_WhenCannotDetermineEnvironmentName_ReturnsError()
    {
        // Arrange
        var userName = "Test User";
        var envName = "Production";
        var entry = CreateHistoryEntry(HistoryEventType.Deleted, HistoryEntryDtoExtensions.KnownEntityTypes.SystemPermissionRole, GetRoleEntityIdentifier(envName, userName));
        entry.EntityIdentifier = "not-a-number";
        entry.Changes.Add(new FieldChangeDto("User ID", null, "user-oid-123"));
        entry.Changes.Add(new FieldChangeDto("RoleType", null, "Reader"));

        var currentSystemPermission = CreateTestSystemPermission();
        currentSystemPermission.Environments.Add(new SystemPermissionEnvironmentDtoRead
        {
            Id = 3,
            Environment = envName,
            SystemPermissionId = currentSystemPermission.Id
        });

        // Act
        var result = await _sut.ExecuteUndoAsync(entry, currentSystemPermission);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result.IsSuccess, Is.False);
            Assert.That(result.ErrorMessage, Does.Contain("Cannot determine environment name"));
        }

        await _mockAdminApiService.DidNotReceive().CreateSystemPermissionRole(Arg.Any<SystemPermissionRoleDtoCreate>());
    }

    [Test]
    public async Task ExecuteUndoAsync_WithDeletedRole_WhenMissingRoleType_ReturnsError()
    {
        // Arrange
        var userName = "Test User";
        var envName = "Production";
        var entry = CreateHistoryEntry(HistoryEventType.Deleted, HistoryEntryDtoExtensions.KnownEntityTypes.SystemPermissionRole, GetRoleEntityIdentifier(envName, userName));
        entry.Changes.Add(new FieldChangeDto("User ID", null, "user-oid-123"));

        var currentSystemPermission = CreateTestSystemPermission();
        currentSystemPermission.Environments.Add(new SystemPermissionEnvironmentDtoRead
        {
            Id = 3,
            Environment = envName,
            SystemPermissionId = currentSystemPermission.Id
        });

        // Act
        var result = await _sut.ExecuteUndoAsync(entry, currentSystemPermission);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result.IsSuccess, Is.False);
            Assert.That(result.ErrorMessage, Does.Contain("missing required RoleType"));
        }

        await _mockAdminApiService.DidNotReceive().CreateSystemPermissionRole(Arg.Any<SystemPermissionRoleDtoCreate>());
    }

    #endregion

    #region ExecuteUndoAsync - Unsupported Operations Tests

    [Test]
    public async Task ExecuteUndoAsync_WithCreatedEvent_ReturnsError()
    {
        // Arrange
        var entry = CreateHistoryEntry(HistoryEventType.Created, HistoryEntryDtoExtensions.KnownEntityTypes.SystemPermissionEnvironment);

        var currentSystemPermission = CreateTestSystemPermission();

        // Act
        var result = await _sut.ExecuteUndoAsync(entry, currentSystemPermission);

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
        var entry = CreateHistoryEntry(HistoryEventType.Updated, HistoryEntryDtoExtensions.KnownEntityTypes.SystemPermissionEnvironment);
        entry.Changes.Add(new FieldChangeDto("Environment", "NewEnv", "OldEnv"));

        var currentSystemPermission = CreateTestSystemPermission();

        // Act
        var result = await _sut.ExecuteUndoAsync(entry, currentSystemPermission);

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
        var entry = CreateHistoryEntry(HistoryEventType.Deleted, "UnsupportedEntityType");
        entry.Changes.Add(new FieldChangeDto("SomeField", null, "SomeValue"));

        var currentSystemPermission = CreateTestSystemPermission();

        // Act
        var result = await _sut.ExecuteUndoAsync(entry, currentSystemPermission);

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

    private static string GetRoleEntityIdentifier(string envName, string userName)
    {
        return $"{envName}:{userName}";
    }

    private static SystemPermissionDtoRead CreateTestSystemPermission()
    {
        return new SystemPermissionDtoRead
        {
            Id = 1,
            Name = "test-permission",
            Description = "Test system permission",
            Environments = new List<SystemPermissionEnvironmentDtoRead>()
        };
    }

    #endregion
}
