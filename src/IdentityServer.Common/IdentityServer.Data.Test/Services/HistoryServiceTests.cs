// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

using IdentityServer.Abstraction.DTO.History;
using IdentityServer.Abstraction.Entities.IdentityServerConfig;
using IdentityServer.Abstraction.Entities.IdentityServerConfig.SystemPermissions;
using IdentityServer.Abstraction.Enums;
using IdentityServer.Data.DuendeEntityExtensions;
using IdentityServer.Data.Entities.Roles;
using IdentityServer.Data.Services;
using IdentityServer.Tests.Common.Builders;

namespace IdentityServer.Data.Test.Services;

[TestFixture]
public class HistoryServiceTests
{
    private HistoryService _historyService;

    [SetUp]
    public void SetUp()
    {
        _historyService = new HistoryService();
    }

    #region TrackVersionChanges Tests

    [Test]
    public void TrackVersionChanges_WithEmptyList_ReturnsEmptyList()
    {
        // Arrange
        var emptyList = new List<ApiResourceExt>();
        var fields = new[] { "Name", "DisplayName" };

        // Act
        var result = _historyService.TrackVersionChanges(
            emptyList,
            fields,
            e => e.Id.ToString());

        // Assert
        Assert.That(result, Is.Empty);
    }

    [Test]
    public void TrackVersionChanges_WithSingleVersion_ReturnsCreationEvent()
    {
        // Arrange
        var dt = new DateTime(2024, 1, 1);
        var entity = new ApiResourceExtBuilder("Test")
            .WithId(1)
            .WithDisplayName("Test Resource")
            .WithCreated(dt, "user1")
            .WithPeriod(dt, DateTime.MaxValue)
            .Build();
        var versions = new List<ApiResourceExt> { entity };
        var fields = new[] { "Name", "DisplayName" };

        // Act
        var result = _historyService.TrackVersionChanges(
            versions,
            fields,
            e => e.Id.ToString());

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result, Has.Count.EqualTo(1));
            var creationEvent = result[0];
            Assert.That(creationEvent.EventType, Is.EqualTo(HistoryEventType.Created));
            Assert.That(creationEvent.EntityType, Is.EqualTo(HistoryEntryDtoExtensions.KnownEntityTypes.ApiResource));
            Assert.That(creationEvent.EntityIdentifier, Is.EqualTo("1"));
            Assert.That(creationEvent.ChangedBy, Is.EqualTo("user1"));
            Assert.That(creationEvent.Timestamp, Is.EqualTo(dt));
            Assert.That(creationEvent.Changes, Has.Count.EqualTo(2));
        }
    }

    [Test]
    public void TrackVersionChanges_CreationTimestamp_UsesMaxOfPeriodStartAndCreated()
    {
        // Arrange - Created date is later than PeriodStart
        var periodStart = new DateTime(2024, 1, 1);
        var createdDate = periodStart.AddDays(4);
        var entity = new ApiResourceExtBuilder("Test")
            .WithId(1)
            .WithDisplayName("Test Resource")
            .WithCreated(createdDate, "user1")
            .WithPeriod(periodStart, DateTime.MaxValue)
            .Build();
        var versions = new List<ApiResourceExt> { entity };
        var fields = new[] { "Name", "DisplayName" };

        // Act
        var result = _historyService.TrackVersionChanges(
            versions,
            fields,
            e => e.Id.ToString());

        // Assert
        Assert.That(result[0].Timestamp, Is.EqualTo(createdDate),
            "Creation timestamp should use Created date when it's later than PeriodStart");
    }

    [Test]
    public void TrackVersionChanges_WithMultipleVersions_ReturnsCreationAndUpdateEvents()
    {
        // Arrange
        var createdDate = new DateTime(2024, 1, 1);
        var updatedDate = createdDate.AddDays(1);
        var version1 = new ApiResourceExtBuilder("Test")
            .WithId(1)
            .WithDisplayName("Test Resource")
            .WithCreated(createdDate, "user1")
            .WithUpdated(createdDate, "user1")
            .WithPeriod(createdDate, updatedDate)
            .Build();
        var version2 = new ApiResourceExtBuilder("Test Updated")
            .WithId(1)
            .WithDisplayName("Test Resource")
            .WithCreated(createdDate, "user1")
            .WithUpdated(updatedDate, "user2")
            .WithPeriod(updatedDate, DateTime.MaxValue)
            .Build();
        var versions = new List<ApiResourceExt> { version1, version2 };
        var fields = new[] { "Name", "DisplayName" };

        // Act
        var result = _historyService.TrackVersionChanges(
            versions,
            fields,
            e => e.Id.ToString());

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result, Has.Count.EqualTo(2));
            Assert.That(result[0].EventType, Is.EqualTo(HistoryEventType.Created));
            Assert.That(result[0].ChangedBy, Is.EqualTo("user1"));
            Assert.That(result[0].Timestamp, Is.EqualTo(createdDate));
            Assert.That(result[0].Changes[0].FieldName, Is.EqualTo("Name"));
            Assert.That(result[0].Changes[0].OldValue, Is.Null);
            Assert.That(result[0].Changes[0].NewValue, Is.EqualTo("Test"));
            Assert.That(result[1].EventType, Is.EqualTo(HistoryEventType.Updated));
            Assert.That(result[1].ChangedBy, Is.EqualTo("user2"));
            Assert.That(result[1].Timestamp, Is.EqualTo(updatedDate));
            Assert.That(result[1].Changes, Has.Count.EqualTo(1));
            Assert.That(result[1].Changes[0].FieldName, Is.EqualTo("Name"));
            Assert.That(result[1].Changes[0].OldValue, Is.EqualTo("Test"));
            Assert.That(result[1].Changes[0].NewValue, Is.EqualTo("Test Updated"));
        }
    }

    [Test]
    public void TrackVersionChanges_WithDeletedEntity_ReturnsDeleteEvent()
    {
        // Arrange
        var createdDate = new DateTime(2024, 1, 1);
        var deletedDate = createdDate.AddDays(1);
        var entity = new ApiResourceExtBuilder("Test")
            .WithId(1)
            .WithDisplayName("Test Resource")
            .WithCreated(createdDate, "user1")
            .WithUpdated(deletedDate, "user2")
            .WithPeriod(createdDate, deletedDate)
            .Build();
        var versions = new List<ApiResourceExt> { entity };
        var fields = new[] { "Name", "DisplayName" };

        // Act
        var result = _historyService.TrackVersionChanges(
            versions,
            fields,
            e => e.Id.ToString());

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result, Has.Count.EqualTo(2));
            var deleteEvent = result[1];
            Assert.That(deleteEvent.EventType, Is.EqualTo(HistoryEventType.Deleted));
            Assert.That(deleteEvent.ChangedBy, Is.EqualTo("user2"));
            Assert.That(deleteEvent.Timestamp, Is.EqualTo(deletedDate));
            Assert.That(deleteEvent.Changes, Is.Empty);
        }
    }

    [Test]
    public void TrackVersionChanges_WithDeletedEntityAndDetailedFlag_ReturnsDeleteEventWithFields()
    {
        // Arrange
        var createdDate = new DateTime(2024, 1, 1);
        var deletedDate = createdDate.AddDays(1);
        var entity = new ApiResourceExtBuilder("Test")
            .WithId(1)
            .WithDisplayName("Test Resource")
            .WithCreated(createdDate, "user1")
            .WithUpdated(deletedDate, "user2")
            .WithPeriod(createdDate, deletedDate)
            .Build();
        var versions = new List<ApiResourceExt> { entity };
        var fields = new[] { "Name", "DisplayName" };

        // Act
        var result = _historyService.TrackVersionChanges(
            versions,
            fields,
            e => e.Id.ToString(),
            withDeleteEventDetailed: true);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result, Has.Count.EqualTo(2));
            var deleteEvent = result[1];
            Assert.That(deleteEvent.EventType, Is.EqualTo(HistoryEventType.Deleted));
            Assert.That(deleteEvent.Changes, Has.Count.EqualTo(2));
        }
    }

    [Test]
    public void TrackVersionChanges_WithNoFieldChanges_ReturnsOnlyEventsWithChanges()
    {
        // Arrange
        var createdDate = new DateTime(2024, 1, 1);
        var updatedDate = createdDate.AddDays(1);
        var version1 = new ApiResourceExtBuilder("Test")
            .WithId(1)
            .WithDisplayName("Test Resource")
            .WithCreated(createdDate, "user1")
            .WithUpdated(createdDate, "user1")
            .WithPeriod(createdDate, updatedDate)
            .Build();
        var version2 = new ApiResourceExtBuilder("Test")
            .WithId(1)
            .WithDisplayName("Test Resource")
            .WithCreated(createdDate, "user1")
            .WithUpdated(updatedDate, "user2")
            .WithPeriod(updatedDate, DateTime.MaxValue)
            .Build();
        var versions = new List<ApiResourceExt> { version1, version2 };
        var fields = new[] { "Name", "DisplayName" };

        // Act
        var result = _historyService.TrackVersionChanges(
            versions,
            fields,
            e => e.Id.ToString());

        // Assert
        Assert.That(result, Has.Count.EqualTo(1));
        Assert.That(result[0].EventType, Is.EqualTo(HistoryEventType.Created));
    }

    #endregion

    #region ProcessAddRemoveEntityVersions Tests

    [Test]
    public void ProcessAddRemoveEntityVersions_WithSingleVersion_ReturnsCreationEvent()
    {
        // Arrange
        var createdDate = new DateTime(2024, 1, 1);
        var entity = new ApiResourceExtBuilder("Test")
            .WithId(1)
            .WithCreated(createdDate, "user1")
            .WithPeriod(createdDate, DateTime.MaxValue)
            .Build();
        var versions = new List<ApiResourceExt> { entity };

        // Act
        var result = _historyService.ProcessAddRemoveEntityVersions(
            versions,
            e => e.Id.ToString(),
            e => new List<FieldChangeDto> { new("Name", e.Name, HistoryEventType.Created) });

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result, Has.Count.EqualTo(1));
            Assert.That(result[0].EventType, Is.EqualTo(HistoryEventType.Created));
            Assert.That(result[0].ChangedBy, Is.EqualTo("user1"));
            Assert.That(result[0].Timestamp, Is.EqualTo(createdDate));
        }
    }

    [Test]
    public void ProcessAddRemoveEntityVersions_WithDeletedEntity_ReturnsCreationAndDeletionEvents()
    {
        // Arrange
        var createdDate = new DateTime(2024, 1, 1);
        var deletedDate = createdDate.AddDays(1);
        var entity = new ApiResourceExtBuilder("Test")
            .WithId(1)
            .WithCreated(createdDate, "user1")
            .WithUpdated(deletedDate, "user2")
            .WithPeriod(createdDate, deletedDate)
            .Build();
        var versions = new List<ApiResourceExt> { entity };

        // Act
        var result = _historyService.ProcessAddRemoveEntityVersions(
            versions,
            e => e.Id.ToString(),
            e => new List<FieldChangeDto> { new("Name", e.Name, HistoryEventType.Created) });

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result, Has.Count.EqualTo(2));
            Assert.That(result[0].EventType, Is.EqualTo(HistoryEventType.Created));
            Assert.That(result[0].Timestamp, Is.EqualTo(createdDate));
            Assert.That(result[0].ChangedBy, Is.EqualTo("user1"));
            Assert.That(result[1].EventType, Is.EqualTo(HistoryEventType.Deleted));
            Assert.That(result[1].Timestamp, Is.EqualTo(deletedDate));
            Assert.That(result[1].ChangedBy, Is.EqualTo("user2"));
        }
    }

    [Test]
    public void ProcessAddRemoveEntityVersions_WithMultipleEntities_ReturnsEventsForEach()
    {
        // Arrange
        var createdDate1 = new DateTime(2024, 1, 1);
        var createdDate2 = createdDate1.AddDays(1);
        var entity1 = new ApiResourceExtBuilder("Test1")
            .WithId(1)
            .WithCreated(createdDate1, "user1")
            .WithPeriod(createdDate1, DateTime.MaxValue)
            .Build();
        var entity2 = new ApiResourceExtBuilder("Test2")
            .WithId(2)
            .WithCreated(createdDate2, "user2")
            .WithPeriod(createdDate2, DateTime.MaxValue)
            .Build();
        var versions = new List<ApiResourceExt> { entity1, entity2 };

        // Act
        var result = _historyService.ProcessAddRemoveEntityVersions(
            versions,
            e => e.Id.ToString(),
            e => new List<FieldChangeDto> { new("Name", e.Name, HistoryEventType.Created) });

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result, Has.Count.EqualTo(2));
            Assert.That(result[0].EntityType, Is.EqualTo(HistoryEntryDtoExtensions.KnownEntityTypes.ApiResource));
            Assert.That(result[1].EntityType, Is.EqualTo(HistoryEntryDtoExtensions.KnownEntityTypes.ApiResource));
            Assert.That(result[0].Timestamp, Is.EqualTo(createdDate1));
            Assert.That(result[1].Timestamp, Is.EqualTo(createdDate2));
        }
    }

    #endregion

    #region ProcessRoleMappingVersions Tests

    [Test]
    public void ProcessRoleMappingVersions_WithSingleMapping_ReturnsCreationEvent()
    {
        // Arrange
        var createdDate = new DateTime(2024, 1, 1);
        var mapping = CreateRoleMapping(
            id: 1,
            roleId: 10,
            mappingType: RoleMapType.UserObjectId,
            value: "Value1",
            description: "Desc1",
            created: createdDate,
            createdBy: "user1",
            periodStart: createdDate,
            periodEnd: DateTime.MaxValue);
        var mappings = new List<RoleMapping> { mapping };
        var roleNameLookup = new Dictionary<int, string> { { 10, "Admin" } };

        // Act
        var result = _historyService.ProcessRoleMappingVersions(
            mappings,
            roleNameLookup,
            m => m.ApiResourceRoleId,
            m => m.MappingType.ToString(),
            m => m.Value,
            m => m.Description);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result, Has.Count.EqualTo(1));
            Assert.That(result[0].EventType, Is.EqualTo(HistoryEventType.Created));
            Assert.That(result[0].EntityIdentifier, Is.EqualTo("Admin:Desc1"));
            Assert.That(result[0].Timestamp, Is.EqualTo(createdDate));
            Assert.That(result[0].Changes, Has.Count.EqualTo(3));
        }
    }

    [Test]
    public void ProcessRoleMappingVersions_WithDeletedMapping_ReturnsCreationAndDeletionEvents()
    {
        // Arrange
        var createdDate = new DateTime(2024, 1, 1);
        var deletedDate = createdDate.AddDays(1);
        var mapping = CreateRoleMapping(
            id: 1,
            roleId: 10,
            mappingType: RoleMapType.UserObjectId,
            value: "Value1",
            description: "Desc1",
            created: createdDate,
            createdBy: "user1",
            updated: deletedDate,
            updatedBy: "user2",
            periodStart: createdDate,
            periodEnd: deletedDate);
        var mappings = new List<RoleMapping> { mapping };
        var roleNameLookup = new Dictionary<int, string> { { 10, "Admin" } };

        // Act
        var result = _historyService.ProcessRoleMappingVersions(
            mappings,
            roleNameLookup,
            m => m.ApiResourceRoleId,
            m => m.MappingType.ToString(),
            m => m.Value,
            m => m.Description);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result, Has.Count.EqualTo(2));
            Assert.That(result[0].EventType, Is.EqualTo(HistoryEventType.Created));
            Assert.That(result[0].Timestamp, Is.EqualTo(createdDate));
            Assert.That(result[1].EventType, Is.EqualTo(HistoryEventType.Deleted));
            Assert.That(result[1].Timestamp, Is.EqualTo(deletedDate));
        }
    }

    #endregion

    #region GetFieldChanges Tests

    [Test]
    public void GetFieldChanges_WithNoChanges_ReturnsEmptyList()
    {
        // Arrange
        var entity1 = new ApiResourceExtBuilder("Test")
            .WithId(1)
            .WithDisplayName("Test Resource")
            .Build();
        var entity2 = new ApiResourceExtBuilder("Test")
            .WithId(1)
            .WithDisplayName("Test Resource")
            .Build();
        var fields = new[] { "Name", "DisplayName" };

        // Act
        var result = _historyService.GetFieldChanges(entity1, entity2, fields);

        // Assert
        Assert.That(result, Is.Empty);
    }

    [Test]
    public void GetFieldChanges_WithPropertyChanges_ReturnsChangedFields()
    {
        // Arrange
        var entity1 = new ApiResourceExtBuilder("Test")
            .WithId(1)
            .WithDisplayName("Test Resource")
            .Build();
        var entity2 = new ApiResourceExtBuilder("Updated")
            .WithId(1)
            .WithDisplayName("Updated Resource")
            .Build();
        var fields = new[] { "Name", "DisplayName" };

        // Act
        var result = _historyService.GetFieldChanges(entity1, entity2, fields);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result, Has.Count.EqualTo(2));
            Assert.That(result[0].FieldName, Is.EqualTo("Name"));
            Assert.That(result[0].NewValue, Is.EqualTo("Updated"));
            Assert.That(result[0].OldValue, Is.EqualTo("Test"));
            Assert.That(result[1].FieldName, Is.EqualTo("DisplayName"));
        }
    }

    [Test]
    public void GetFieldChanges_WithNullOldEntity_ComparesWithNull()
    {
        // Arrange
        var entity = new ApiResourceExtBuilder("Test")
            .WithId(1)
            .WithDisplayName("Test Resource")
            .Build();
        var fields = new[] { "Name", "DisplayName" };

        // Act
        var result = _historyService.GetFieldChanges(null, entity, fields);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result, Has.Count.EqualTo(2));
            Assert.That(result[0].OldValue, Is.EqualTo(string.Empty));
        }
    }

    [Test]
    public void GetFieldChanges_WithDateTimeValues_ComparesWithTolerance()
    {
        // Arrange
        var entity1 = new ApiResourceExtBuilder("Test")
            .WithId(1)
            .WithCreated(new DateTime(2024, 1, 1, 12, 0, 0))
            .Build();
        var entity2 = new ApiResourceExtBuilder("Test")
            .WithId(1)
            .WithCreated(new DateTime(2024, 1, 1, 12, 0, 0, 500))
            .Build();
        var fields = new[] { "Created" };

        // Act
        var result = _historyService.GetFieldChanges(entity1, entity2, fields);

        // Assert
        Assert.That(result, Is.Empty);
    }

    [Test]
    public void GetFieldChanges_WithInvalidFieldName_IgnoresField()
    {
        // Arrange
        var entity1 = new ApiResourceExtBuilder("Test")
            .WithId(1)
            .Build();
        var entity2 = new ApiResourceExtBuilder("Updated")
            .WithId(1)
            .Build();
        var fields = new[] { "NonExistentField", "Name" };

        // Act
        var result = _historyService.GetFieldChanges(entity1, entity2, fields);

        // Assert
        Assert.That(result, Has.Count.EqualTo(1));
        Assert.That(result[0].FieldName, Is.EqualTo("Name"));
    }

    #endregion

    #region GetEntityFields Tests

    [Test]
    public void GetEntityFields_ForCreation_ReturnsFieldsWithCreatedEventType()
    {
        // Arrange
        var entity = new ApiResourceExtBuilder("Test")
            .WithId(1)
            .WithDisplayName("Test Resource")
            .Build();
        var fields = new[] { "Name", "DisplayName" };

        // Act
        var result = _historyService.GetEntityFields(entity, fields, forDeletion: false);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result, Has.Count.EqualTo(2));
            Assert.That(result[0].NewValue, Is.EqualTo("Test"));
            Assert.That(result[0].OldValue, Is.Null);
        }
    }

    [Test]
    public void GetEntityFields_ForDeletion_ReturnsFieldsWithDeletedEventType()
    {
        // Arrange
        var entity = new ApiResourceExtBuilder("Test")
            .WithId(1)
            .WithDisplayName("Test Resource")
            .Build();
        var fields = new[] { "Name", "DisplayName" };

        // Act
        var result = _historyService.GetEntityFields(entity, fields, forDeletion: true);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result, Has.Count.EqualTo(2));
            Assert.That(result[0].NewValue, Is.Null);
            Assert.That(result[0].OldValue, Is.EqualTo("Test"));
        }
    }

    [Test]
    public void GetEntityFields_WithNullValue_FormatsAsEmptyString()
    {
        // Arrange
        var entity = new ApiResourceExtBuilder("Test")
            .WithId(1)
            .Build();
        entity.CreatedBy = null; // Explicitly set to null after build
        var fields = new[] { "CreatedBy" };

        // Act
        var result = _historyService.GetEntityFields(entity, fields);

        // Assert
        Assert.That(result[0].NewValue, Is.EqualTo(string.Empty));
    }

    [Test]
    public void GetEntityFields_WithDateTimeValue_FormatsAsIso8601()
    {
        // Arrange
        var date = new DateTime(2024, 1, 1, 12, 0, 0, DateTimeKind.Utc);
        var entity = new ApiResourceExtBuilder("Test")
            .WithId(1)
            .WithCreated(date)
            .Build();
        var fields = new[] { "Created" };

        // Act
        var result = _historyService.GetEntityFields(entity, fields);

        // Assert
        Assert.That(result[0].NewValue, Is.EqualTo(date.ToString("O")));
    }

    #endregion

    #region HistoryDisplayNameAttribute Tests

    [Test]
    public void GetFieldChanges_WithHistoryDisplayNameAttribute_UsesCustomDisplayName()
    {
        // Arrange
        var entity1 = new SystemPermissionRole
        {
            OId = "user-123",
            Name = "Test User",
            SystemPermissionEnvironmentId = 1,
            RoleType = SystemPermissionRoleType.Reader
        };
        var entity2 = new SystemPermissionRole
        {
            OId = "user-456",
            Name = "Test User",
            SystemPermissionEnvironmentId = 1,
            RoleType = SystemPermissionRoleType.Reader
        };
        var fields = new[] { "OId" };

        // Act
        var result = _historyService.GetFieldChanges(entity1, entity2, fields);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result, Has.Count.EqualTo(1));
            Assert.That(result[0].FieldName, Is.EqualTo("User ID"));
            Assert.That(result[0].NewValue, Is.EqualTo("user-456"));
            Assert.That(result[0].OldValue, Is.EqualTo("user-123"));
        }
    }

    [Test]
    public void GetFieldChanges_WithoutHistoryDisplayNameAttribute_UsesPropertyName()
    {
        // Arrange
        var entity1 = new SystemPermissionRole
        {
            OId = "user-123",
            Name = "User One",
            SystemPermissionEnvironmentId = 1,
            RoleType = SystemPermissionRoleType.Reader
        };
        var entity2 = new SystemPermissionRole
        {
            OId = "user-123",
            Name = "User Two",
            SystemPermissionEnvironmentId = 1,
            RoleType = SystemPermissionRoleType.Reader
        };
        var fields = new[] { "Name" };

        // Act
        var result = _historyService.GetFieldChanges(entity1, entity2, fields);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result, Has.Count.EqualTo(1));
            Assert.That(result[0].FieldName, Is.EqualTo("Name"));
        }
    }

    [Test]
    public void GetEntityFields_WithHistoryDisplayNameAttribute_UsesCustomDisplayName()
    {
        // Arrange
        var entity = new SystemPermissionRole
        {
            OId = "user-789",
            Name = "Test User",
            SystemPermissionEnvironmentId = 1,
            RoleType = SystemPermissionRoleType.Reader
        };
        var fields = new[] { "OId" };

        // Act
        var result = _historyService.GetEntityFields(entity, fields);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result, Has.Count.EqualTo(1));
            Assert.That(result[0].FieldName, Is.EqualTo("User ID"));
            Assert.That(result[0].NewValue, Is.EqualTo("user-789"));
        }
    }

    [Test]
    public void GetEntityFields_WithMultiplePropertiesWithAttributes_UsesCorrectDisplayNames()
    {
        // Arrange
        var entity = new SystemPermissionRole
        {
            OId = "user-123",
            Name = "Test User",
            SystemPermissionEnvironmentId = 1,
            RoleType = SystemPermissionRoleType.Reader
        };
        var fields = new[] { "OId", "Name", "SystemPermissionEnvironmentId" };

        // Act
        var result = _historyService.GetEntityFields(entity, fields);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result, Has.Count.EqualTo(3));
            Assert.That(result[0].FieldName, Is.EqualTo("User ID"));
            Assert.That(result[1].FieldName, Is.EqualTo("Name"));
            Assert.That(result[2].FieldName, Is.EqualTo("SystemPermissionEnvironmentId"));
        }
    }

    [Test]
    public void TrackVersionChanges_WithHistoryDisplayNameAttribute_UsesCustomDisplayNamesInEvents()
    {
        // Arrange
        var dt = new DateTime(2024, 1, 1);
        var entity = new SystemPermissionRole
        {
            OId = "user-123",
            Name = "Test User",
            SystemPermissionEnvironmentId = 1,
            RoleType = SystemPermissionRoleType.Reader,
            Created = dt,
            CreatedBy = "admin",
            ValidFrom = dt,
            ValidTo = DateTime.MaxValue
        };
        var versions = new List<SystemPermissionRole> { entity };
        var fields = new[] { "OId", "Name" };

        // Act
        var result = _historyService.TrackVersionChanges(
            versions,
            fields,
            e => e.OId);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result, Has.Count.EqualTo(1));
            var creationEvent = result[0];
            Assert.That(creationEvent.EntityType, Is.EqualTo(HistoryEntryDtoExtensions.KnownEntityTypes.SystemPermissionRole));
            Assert.That(creationEvent.Changes, Has.Count.EqualTo(2));
            Assert.That(creationEvent.Changes[0].FieldName, Is.EqualTo("User ID"));
            Assert.That(creationEvent.Changes[1].FieldName, Is.EqualTo("Name"));
        }
    }

    #endregion

    #region Test Helper Classes

    private static RoleMapping CreateRoleMapping(
        int id,
        int roleId,
        RoleMapType mappingType,
        string value,
        string description = null,
        DateTime? created = null,
        string createdBy = null,
        DateTime? updated = null,
        string updatedBy = null,
        DateTime? periodStart = null,
        DateTime? periodEnd = null)
    {
        return new RoleMapping
        {
            Id = id,
            ApiResourceRoleId = roleId,
            MappingType = mappingType,
            Value = value,
            Description = description,
            Created = created,
            CreatedBy = createdBy,
            Updated = updated,
            UpdatedBy = updatedBy,
            ValidFrom = periodStart ?? DateTime.MinValue,
            ValidTo = periodEnd ?? DateTime.MaxValue
        };
    }

    #endregion
}
