// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

using Bunit;
using Microsoft.Extensions.DependencyInjection;
using NSubstitute;
using Telerik.Blazor.Components;
using IdentityServer.Abstraction.DTO.History;
using IdentityServer.Abstraction.Enums;
using IdentityServer.AdminPortal.Web.Components.History;
using IdentityServer.AdminPortal.Web.Services;
using IdentityServer.AdminPortal.Web.Services.History;

namespace IdentityServer.AdminPortal.Web.Tests.Components.History;

public class HistoryTimelineTests
{
    private static readonly TimeSpan _assertionTimeout = TimeSpan.FromSeconds(10);
    private Bunit.TestContext _ctx;
    private IHistoryUndoService _mockUndoService;
    private NotificationService _mockNotificationService;

    [SetUp]
    public void Setup()
    {
        _ctx = new Bunit.TestContext();
        _ctx.JSInterop.Mode = JSRuntimeMode.Loose;

        _mockUndoService = Substitute.For<IHistoryUndoService>();
        _mockUndoService.CanUndo(Arg.Any<HistoryEntryDto>(), Arg.Any<Abstraction.DTO.Clients.ClientDtoRead>())
            .Returns(UndoEligibility.Ineligible("Test: No parent entity provided"));
        _mockUndoService.CanUndo(Arg.Any<HistoryEntryDto>(), Arg.Any<Abstraction.DTO.ApiResources.ApiResourceDtoRead>())
            .Returns(UndoEligibility.Ineligible("Test: No parent entity provided"));
        _mockUndoService.CanUndo(Arg.Any<HistoryEntryDto>(), Arg.Any<Abstraction.DTO.SystemPermissions.SystemPermissionDtoRead>())
            .Returns(UndoEligibility.Ineligible("Test: No parent entity provided"));

        _mockNotificationService = Substitute.For<NotificationService>();

        _ctx.Services.AddSingleton(_mockUndoService);
        _ctx.Services.AddSingleton(_mockNotificationService);
    }

    [TearDown]
    public void TearDown()
    {
        _ctx?.Dispose();
    }

    [Test]
    public async Task Component_WhenHistoryEntriesIsNull_DisplaysNoHistoryMessage()
    {
        // Arrange & Act
        var cut = RenderHistoryTimeline(null);

        // Assert
        await RenderAndAssert(cut, () =>
        {
            var alert = cut.Find(".alert.alert-info");
            Assert.That(alert.TextContent.Trim(), Is.EqualTo("No history entries to display."));
        });
    }

    [Test]
    public async Task Component_WhenHistoryEntriesIsEmpty_DisplaysNoHistoryMessage()
    {
        // Arrange & Act
        var cut = RenderHistoryTimeline(new List<HistoryEntryDto>());

        // Assert
        await RenderAndAssert(cut, () =>
        {
            var alert = cut.Find(".alert.alert-info");
            Assert.That(alert.TextContent.Trim(), Is.EqualTo("No history entries to display."));
        });
    }

    [Test]
    public async Task EventBadge_WhenEventTypeIsCreated_DisplaysSuccessBadge()
    {
        // Arrange
        var entries = new List<HistoryEntryDto>
        {
            new()
            {
                Timestamp = new DateTime(2024, 1, 1, 10, 0, 0),
                EventType = HistoryEventType.Created,
                EntityType = "SystemPermission",
                EntityIdentifier = "1",
                ChangedBy = "admin@test.com",
                Changes = new List<FieldChangeDto>()
            }
        };

        // Act
        var cut = RenderHistoryTimeline(entries);

        // Assert
        await RenderAndAssert(cut, () =>
        {
            var badge = cut.Find(".badge.bg-success");
            Assert.That(badge.TextContent, Does.Contain("Created"));
        });
    }

    [Test]
    public async Task EventBadge_WhenEventTypeIsUpdated_DisplaysInfoBadge()
    {
        // Arrange
        var entries = new List<HistoryEntryDto>
        {
            new()
            {
                Timestamp = new DateTime(2024, 1, 1, 10, 0, 0),
                EventType = HistoryEventType.Updated,
                EntityType = "SystemPermission",
                EntityIdentifier = "1",
                ChangedBy = "admin@test.com",
                Changes = new List<FieldChangeDto>()
            }
        };

        // Act
        var cut = RenderHistoryTimeline(entries);

        // Assert
        await RenderAndAssert(cut, () =>
        {
            var badge = cut.Find(".badge.bg-primary");
            Assert.That(badge.TextContent, Does.Contain("Updated"));
        });
    }

    [Test]
    public async Task EventBadge_WhenEventTypeIsDeleted_DisplaysDangerBadge()
    {
        // Arrange
        var entries = new List<HistoryEntryDto>
        {
            new()
            {
                Timestamp = new DateTime(2024, 1, 1, 10, 0, 0),
                EventType = HistoryEventType.Deleted,
                EntityType = "SystemPermission",
                EntityIdentifier = "1",
                ChangedBy = "admin@test.com",
                Changes = new List<FieldChangeDto>()
            }
        };

        // Act
        var cut = RenderHistoryTimeline(entries);

        // Assert
        await RenderAndAssert(cut, () =>
        {
            var badge = cut.Find(".badge.bg-danger");
            Assert.That(badge.TextContent, Does.Contain("Deleted"));
        });
    }

    [Test]
    public async Task Component_WhenMultipleEntries_RendersHistoryChangesDisplay()
    {
        // Arrange
        var entries = new List<HistoryEntryDto>
        {
            new()
            {
                Timestamp = new DateTime(2024, 1, 1, 10, 0, 0),
                EventType = HistoryEventType.Created,
                EntityType = "SystemPermission",
                EntityIdentifier = "1",
                ChangedBy = "admin@test.com",
                Changes = new List<FieldChangeDto>()
            },
            new()
            {
                Timestamp = new DateTime(2024, 1, 2, 10, 0, 0),
                EventType = HistoryEventType.Updated,
                EntityType = "Environment",
                EntityIdentifier = "2",
                ChangedBy = "user@test.com",
                Changes = new List<FieldChangeDto>()
            },
            new()
            {
                Timestamp = new DateTime(2024, 1, 3, 10, 0, 0),
                EventType = HistoryEventType.Deleted,
                EntityType = "Role",
                EntityIdentifier = "3",
                ChangedBy = "superuser@test.com",
                Changes = new List<FieldChangeDto>()
            }
        };

        // Act
        var cut = RenderHistoryTimeline(entries);

        // Assert
        await RenderAndAssert(cut, () =>
        {
            var changesDisplays = cut.FindComponents<HistoryChangesDisplay>();
            Assert.That(changesDisplays, Has.Count.EqualTo(3));
        });
    }

    [Test]
    public async Task Search_WhenSearchTextIsEmpty_DisplaysAllEntries()
    {
        // Arrange
        var entries = new List<HistoryEntryDto>
        {
            new()
            {
                Timestamp = new DateTime(2024, 1, 1, 10, 0, 0),
                EventType = HistoryEventType.Created,
                EntityType = "SystemPermission",
                EntityIdentifier = "1",
                ChangedBy = "admin@test.com",
                Changes = new List<FieldChangeDto>()
            },
            new()
            {
                Timestamp = new DateTime(2024, 1, 2, 10, 0, 0),
                EventType = HistoryEventType.Updated,
                EntityType = "Environment",
                EntityIdentifier = "2",
                ChangedBy = "user@test.com",
                Changes = new List<FieldChangeDto>()
            }
        };

        // Act
        var cut = RenderHistoryTimeline(entries);

        // Assert
        await RenderAndAssert(cut, () =>
        {
            var changesDisplays = cut.FindComponents<HistoryChangesDisplay>();
            Assert.That(changesDisplays, Has.Count.EqualTo(2));
        });
    }

    [Test]
    public async Task Search_WithEventTypeMatch_FiltersCorrectlyAsync()
    {
        // Arrange
        var entries = new List<HistoryEntryDto>
        {
            new()
            {
                Timestamp = new DateTime(2024, 1, 1, 10, 0, 0),
                EventType = HistoryEventType.Created,
                EntityType = "SystemPermission",
                EntityIdentifier = "1",
                ChangedBy = "admin@test.com",
                Changes = new List<FieldChangeDto>()
            },
            new()
            {
                Timestamp = new DateTime(2024, 1, 2, 10, 0, 0),
                EventType = HistoryEventType.Updated,
                EntityType = "Environment",
                EntityIdentifier = "2",
                ChangedBy = "user@test.com",
                Changes = new List<FieldChangeDto>()
            },
            new()
            {
                Timestamp = new DateTime(2024, 1, 3, 10, 0, 0),
                EventType = HistoryEventType.Deleted,
                EntityType = "Role",
                EntityIdentifier = "3",
                ChangedBy = "superuser@test.com",
                Changes = new List<FieldChangeDto>()
            }
        };

        var cut = RenderHistoryTimeline(entries);

        // Act
        await SetSearchBoxValue(cut, "created");

        // Assert
        await RenderAndAssert(cut, () =>
        {
            var changesDisplays = cut.FindComponents<HistoryChangesDisplay>();
            Assert.That(changesDisplays, Has.Count.EqualTo(1));
        });
    }

    [Test]
    public async Task Search_WithEntityTypeMatch_FiltersCorrectlyAsync()
    {
        // Arrange
        var entries = new List<HistoryEntryDto>
        {
            new()
            {
                Timestamp = new DateTime(2024, 1, 1, 10, 0, 0),
                EventType = HistoryEventType.Created,
                EntityType = "SystemPermission",
                EntityIdentifier = "1",
                ChangedBy = "admin@test.com",
                Changes = new List<FieldChangeDto>()
            },
            new()
            {
                Timestamp = new DateTime(2024, 1, 2, 10, 0, 0),
                EventType = HistoryEventType.Updated,
                EntityType = "Environment",
                EntityIdentifier = "2",
                ChangedBy = "user@test.com",
                Changes = new List<FieldChangeDto>()
            },
            new()
            {
                Timestamp = new DateTime(2024, 1, 3, 10, 0, 0),
                EventType = HistoryEventType.Updated,
                EntityType = "Role",
                EntityIdentifier = "3",
                ChangedBy = "superuser@test.com",
                Changes = new List<FieldChangeDto>()
            }
        };

        var cut = RenderHistoryTimeline(entries);

        // Act
        await SetSearchBoxValue(cut, "Environment");

        // Assert
        await RenderAndAssert(cut, () =>
        {
            var changesDisplays = cut.FindComponents<HistoryChangesDisplay>();
            Assert.That(changesDisplays, Has.Count.EqualTo(1));
        });
    }

    [Test]
    public async Task Search_WithEntityIdentifierMatch_FiltersCorrectlyAsync()
    {
        // Arrange
        var entries = new List<HistoryEntryDto>
        {
            new()
            {
                Timestamp = new DateTime(2024, 1, 1, 10, 0, 0),
                EventType = HistoryEventType.Created,
                EntityType = "SystemPermission",
                EntityIdentifier = "perm-123-abc",
                ChangedBy = "admin@test.com",
                Changes = new List<FieldChangeDto>()
            },
            new()
            {
                Timestamp = new DateTime(2024, 1, 2, 10, 0, 0),
                EventType = HistoryEventType.Updated,
                EntityType = "Environment",
                EntityIdentifier = "env-456-def",
                ChangedBy = "user@test.com",
                Changes = new List<FieldChangeDto>()
            }
        };

        var cut = RenderHistoryTimeline(entries);

        // Act
        await SetSearchBoxValue(cut, "456");

        // Assert
        await RenderAndAssert(cut, () =>
        {
            var changesDisplays = cut.FindComponents<HistoryChangesDisplay>();
            Assert.That(changesDisplays, Has.Count.EqualTo(1));
        });
    }

    [Test]
    public async Task Search_WithChangedByMatch_FiltersCorrectlyAsync()
    {
        // Arrange
        var entries = new List<HistoryEntryDto>
        {
            new()
            {
                Timestamp = new DateTime(2024, 1, 1, 10, 0, 0),
                EventType = HistoryEventType.Created,
                EntityType = "SystemPermission",
                EntityIdentifier = "1",
                ChangedBy = "admin@test.com",
                Changes = new List<FieldChangeDto>()
            },
            new()
            {
                Timestamp = new DateTime(2024, 1, 2, 10, 0, 0),
                EventType = HistoryEventType.Updated,
                EntityType = "Environment",
                EntityIdentifier = "2",
                ChangedBy = "user@test.com",
                Changes = new List<FieldChangeDto>()
            },
            new()
            {
                Timestamp = new DateTime(2024, 1, 3, 10, 0, 0),
                EventType = HistoryEventType.Updated,
                EntityType = "Role",
                EntityIdentifier = "3",
                ChangedBy = "superuser@test.com",
                Changes = new List<FieldChangeDto>()
            }
        };

        var cut = RenderHistoryTimeline(entries);

        // Act
        await SetSearchBoxValue(cut, "admin");

        // Assert
        await RenderAndAssert(cut, () =>
        {
            var changesDisplays = cut.FindComponents<HistoryChangesDisplay>();
            Assert.That(changesDisplays, Has.Count.EqualTo(1));
        });
    }

    [Test]
    public async Task Search_WithFieldNameMatch_FiltersCorrectlyAsync()
    {
        // Arrange
        var entries = new List<HistoryEntryDto>
        {
            new()
            {
                Timestamp = new DateTime(2024, 1, 1, 10, 0, 0),
                EventType = HistoryEventType.Updated,
                EntityType = "SystemPermission",
                EntityIdentifier = "1",
                ChangedBy = "admin@test.com",
                Changes = new List<FieldChangeDto>
                {
                    new() { FieldName = "Name", OldValue = "OldName", NewValue = "NewName" }
                }
            },
            new()
            {
                Timestamp = new DateTime(2024, 1, 2, 10, 0, 0),
                EventType = HistoryEventType.Updated,
                EntityType = "Environment",
                EntityIdentifier = "2",
                ChangedBy = "user@test.com",
                Changes = new List<FieldChangeDto>
                {
                    new() { FieldName = "Description", OldValue = "OldDesc", NewValue = "NewDesc" }
                }
            }
        };

        var cut = RenderHistoryTimeline(entries);

        // Act
        await SetSearchBoxValue(cut, "Description");

        // Assert
        await RenderAndAssert(cut, () =>
        {
            var changesDisplays = cut.FindComponents<HistoryChangesDisplay>();
            Assert.That(changesDisplays, Has.Count.EqualTo(1));
        });
    }

    [Test]
    public async Task Search_WithOldValueMatch_FiltersCorrectlyAsync()
    {
        // Arrange
        var entries = new List<HistoryEntryDto>
        {
            new()
            {
                Timestamp = new DateTime(2024, 1, 1, 10, 0, 0),
                EventType = HistoryEventType.Updated,
                EntityType = "SystemPermission",
                EntityIdentifier = "1",
                ChangedBy = "admin@test.com",
                Changes = new List<FieldChangeDto>
                {
                    new() { FieldName = "Name", OldValue = "OriginalName", NewValue = "UpdatedName" }
                }
            },
            new()
            {
                Timestamp = new DateTime(2024, 1, 2, 10, 0, 0),
                EventType = HistoryEventType.Updated,
                EntityType = "Environment",
                EntityIdentifier = "2",
                ChangedBy = "user@test.com",
                Changes = new List<FieldChangeDto>
                {
                    new() { FieldName = "Name", OldValue = "OldEnvName", NewValue = "NewEnvName" }
                }
            }
        };

        var cut = RenderHistoryTimeline(entries);

        // Act
        await SetSearchBoxValue(cut, "OriginalName");

        // Assert
        await RenderAndAssert(cut, () =>
        {
            var changesDisplays = cut.FindComponents<HistoryChangesDisplay>();
            Assert.That(changesDisplays, Has.Count.EqualTo(1));
        });
    }

    [Test]
    public async Task Search_WithNewValueMatch_FiltersCorrectlyAsync()
    {
        // Arrange
        var entries = new List<HistoryEntryDto>
        {
            new()
            {
                Timestamp = new DateTime(2024, 1, 1, 10, 0, 0),
                EventType = HistoryEventType.Updated,
                EntityType = "SystemPermission",
                EntityIdentifier = "1",
                ChangedBy = "admin@test.com",
                Changes = new List<FieldChangeDto>
                {
                    new() { FieldName = "Status", OldValue = "Inactive", NewValue = "Active" }
                }
            },
            new()
            {
                Timestamp = new DateTime(2024, 1, 2, 10, 0, 0),
                EventType = HistoryEventType.Updated,
                EntityType = "Environment",
                EntityIdentifier = "2",
                ChangedBy = "user@test.com",
                Changes = new List<FieldChangeDto>
                {
                    new() { FieldName = "Status", OldValue = "Active", NewValue = "Disabled" }
                }
            }
        };

        var cut = RenderHistoryTimeline(entries);

        // Act
        await SetSearchBoxValue(cut, "Disabled");

        // Assert
        await RenderAndAssert(cut, () =>
        {
            var changesDisplays = cut.FindComponents<HistoryChangesDisplay>();
            Assert.That(changesDisplays, Has.Count.EqualTo(1));
        });
    }

    [Test]
    public async Task Search_IsCaseInsensitive_FiltersCorrectly()
    {
        // Arrange
        var entries = new List<HistoryEntryDto>
        {
            new()
            {
                Timestamp = new DateTime(2024, 1, 1, 10, 0, 0),
                EventType = HistoryEventType.Created,
                EntityType = "SystemPermission",
                EntityIdentifier = "1",
                ChangedBy = "admin@test.com",
                Changes = new List<FieldChangeDto>()
            },
            new()
            {
                Timestamp = new DateTime(2024, 1, 2, 10, 0, 0),
                EventType = HistoryEventType.Updated,
                EntityType = "Environment",
                EntityIdentifier = "2",
                ChangedBy = "user@test.com",
                Changes = new List<FieldChangeDto>()
            }
        };

        var cut = RenderHistoryTimeline(entries);

        // Act
        await SetSearchBoxValue(cut, "ENVIRONMENT");

        // Assert
        await RenderAndAssert(cut, () =>
        {
            var changesDisplays = cut.FindComponents<HistoryChangesDisplay>();
            Assert.That(changesDisplays, Has.Count.EqualTo(1));
        });
    }

    [Test]
    public async Task Search_WithNoMatches_DisplaysNoHistoryMessageAsync()
    {
        // Arrange
        var entries = new List<HistoryEntryDto>
        {
            new()
            {
                Timestamp = new DateTime(2024, 1, 1, 10, 0, 0),
                EventType = HistoryEventType.Created,
                EntityType = "SystemPermission",
                EntityIdentifier = "1",
                ChangedBy = "admin@test.com",
                Changes = new List<FieldChangeDto>()
            }
        };

        var cut = RenderHistoryTimeline(entries);

        // Act
        await SetSearchBoxValue(cut, "NonExistentSearchTerm");

        // Assert
        await RenderAndAssert(cut, () =>
        {
            var alert = cut.Find(".alert.alert-info");
            Assert.That(alert.TextContent.Trim(), Is.EqualTo("No history entries match the current filters."));
        });
    }

    [Test]
    public async Task Search_WithMultipleMatches_DisplaysAllMatchingEntriesAsync()
    {
        // Arrange
        var entries = new List<HistoryEntryDto>
        {
            new()
            {
                Timestamp = new DateTime(2024, 1, 1, 10, 0, 0),
                EventType = HistoryEventType.Created,
                EntityType = "SystemPermission",
                EntityIdentifier = "1",
                ChangedBy = "admin@test.com",
                Changes = new List<FieldChangeDto>()
            },
            new()
            {
                Timestamp = new DateTime(2024, 1, 2, 10, 0, 0),
                EventType = HistoryEventType.Updated,
                EntityType = "SystemPermission",
                EntityIdentifier = "2",
                ChangedBy = "user@test.com",
                Changes = new List<FieldChangeDto>()
            },
            new()
            {
                Timestamp = new DateTime(2024, 1, 3, 10, 0, 0),
                EventType = HistoryEventType.Deleted,
                EntityType = "Environment",
                EntityIdentifier = "3",
                ChangedBy = "superuser@test.com",
                Changes = new List<FieldChangeDto>()
            }
        };

        var cut = RenderHistoryTimeline(entries);

        // Act
        await SetSearchBoxValue(cut, "SystemPermission");

        // Assert
        await RenderAndAssert(cut, () =>
        {
            var changesDisplays = cut.FindComponents<HistoryChangesDisplay>();
            Assert.That(changesDisplays, Has.Count.EqualTo(2));
        });
    }

    [Test]
    public async Task Search_WithNullEntityIdentifier_HandlesGracefullyAsync()
    {
        // Arrange
        var entries = new List<HistoryEntryDto>
        {
            new()
            {
                Timestamp = new DateTime(2024, 1, 1, 10, 0, 0),
                EventType = HistoryEventType.Created,
                EntityType = "SystemPermission",
                EntityIdentifier = null,
                ChangedBy = "admin@test.com",
                Changes = new List<FieldChangeDto>()
            }
        };

        var cut = RenderHistoryTimeline(entries);

        // Act
        await SetSearchBoxValue(cut, "SystemPermission");

        // Assert
        await RenderAndAssert(cut, () =>
        {
            var changesDisplays = cut.FindComponents<HistoryChangesDisplay>();
            Assert.That(changesDisplays, Has.Count.EqualTo(1));
        });
    }

    [Test]
    public async Task Search_WithNullChangedBy_HandlesGracefullyAsync()
    {
        // Arrange
        var entries = new List<HistoryEntryDto>
        {
            new()
            {
                Timestamp = new DateTime(2024, 1, 1, 10, 0, 0),
                EventType = HistoryEventType.Created,
                EntityType = "SystemPermission",
                EntityIdentifier = "1",
                ChangedBy = null,
                Changes = new List<FieldChangeDto>()
            }
        };

        var cut = RenderHistoryTimeline(entries);

        // Act
        await SetSearchBoxValue(cut, "SystemPermission");

        // Assert
        await RenderAndAssert(cut, () =>
        {
            var changesDisplays = cut.FindComponents<HistoryChangesDisplay>();
            Assert.That(changesDisplays, Has.Count.EqualTo(1));
        });
    }

    [Test]
    public async Task Search_WithNullChanges_HandlesGracefullyAsync()
    {
        // Arrange
        var entries = new List<HistoryEntryDto>
        {
            new()
            {
                Timestamp = new DateTime(2024, 1, 1, 10, 0, 0),
                EventType = HistoryEventType.Created,
                EntityType = "SystemPermission",
                EntityIdentifier = "1",
                ChangedBy = "admin@test.com",
                Changes = null
            }
        };

        var cut = RenderHistoryTimeline(entries);

        // Act
        await SetSearchBoxValue(cut, "SystemPermission");

        // Assert
        await RenderAndAssert(cut, () =>
        {
            var changesDisplays = cut.FindComponents<HistoryChangesDisplay>();
            Assert.That(changesDisplays, Has.Count.EqualTo(1));
        });
    }

    [Test]
    public async Task Search_WithPartialMatch_FiltersCorrectlyAsync()
    {
        // Arrange
        var entries = new List<HistoryEntryDto>
        {
            new()
            {
                Timestamp = new DateTime(2024, 1, 1, 10, 0, 0),
                EventType = HistoryEventType.Created,
                EntityType = "SystemPermission",
                EntityIdentifier = "1",
                ChangedBy = "admin@test.com",
                Changes = new List<FieldChangeDto>()
            },
            new()
            {
                Timestamp = new DateTime(2024, 1, 2, 10, 0, 0),
                EventType = HistoryEventType.Updated,
                EntityType = "Environment",
                EntityIdentifier = "2",
                ChangedBy = "user@test.com",
                Changes = new List<FieldChangeDto>()
            }
        };

        var cut = RenderHistoryTimeline(entries);

        // Act
        await SetSearchBoxValue(cut, "Perm");

        // Assert
        await RenderAndAssert(cut, () =>
        {
            var changesDisplays = cut.FindComponents<HistoryChangesDisplay>();
            Assert.That(changesDisplays, Has.Count.EqualTo(1));
        });
    }

    [Test]
    public async Task ResetFiltersButton_WhenClicked_ClearsSearchTextAndFilters()
    {
        // Arrange
        var entries = new List<HistoryEntryDto>
        {
            new()
            {
                Timestamp = new DateTime(2024, 1, 1, 10, 0, 0),
                EventType = HistoryEventType.Created,
                EntityType = "SystemPermission",
                EntityIdentifier = "1",
                ChangedBy = "admin@test.com",
                Changes = new List<FieldChangeDto>()
            },
            new()
            {
                Timestamp = new DateTime(2024, 1, 2, 10, 0, 0),
                EventType = HistoryEventType.Updated,
                EntityType = "Environment",
                EntityIdentifier = "2",
                ChangedBy = "user@test.com",
                Changes = new List<FieldChangeDto>()
            }
        };

        var cut = RenderHistoryTimeline(entries);

        // Apply search filter first
        await SetSearchBoxValue(cut, "SystemPermission");

        // Verify filter is applied (only 1 entry shown)
        await RenderAndAssert(cut, () =>
        {
            var changesDisplays = cut.FindComponents<HistoryChangesDisplay>();
            Assert.That(changesDisplays, Has.Count.EqualTo(1));
        });

        // Act - Click Reset Filters button
        await ClickResetFiltersButton(cut);

        // Assert - All entries should be displayed
        await RenderAndAssert(cut, () =>
        {
            var changesDisplays = cut.FindComponents<HistoryChangesDisplay>();
            Assert.That(changesDisplays, Has.Count.EqualTo(2));
        });
    }

    [Test]
    public async Task ResetFiltersButton_WhenClicked_ClearsSearchBoxValue()
    {
        // Arrange
        var entries = new List<HistoryEntryDto>
        {
            new()
            {
                Timestamp = new DateTime(2024, 1, 1, 10, 0, 0),
                EventType = HistoryEventType.Created,
                EntityType = "SystemPermission",
                EntityIdentifier = "1",
                ChangedBy = "admin@test.com",
                Changes = new List<FieldChangeDto>()
            }
        };

        var cut = RenderHistoryTimeline(entries);

        // Apply search filter first
        await SetSearchBoxValue(cut, "TestSearchValue");

        // Act - Click Reset Filters button
        await ClickResetFiltersButton(cut);

        // Assert - Search box should be cleared
        await RenderAndAssert(cut, () =>
        {
            var textBox = cut.FindComponent<TelerikTextBox>();
            Assert.That(textBox.Instance.Value, Is.Empty);
        });
    }

    [Test]
    public async Task ResetGridButton_WhenClicked_ResetsGridStateAndClearsSearch()
    {
        // Arrange
        var entries = new List<HistoryEntryDto>
        {
            new()
            {
                Timestamp = new DateTime(2024, 1, 1, 10, 0, 0),
                EventType = HistoryEventType.Created,
                EntityType = "SystemPermission",
                EntityIdentifier = "1",
                ChangedBy = "admin@test.com",
                Changes = new List<FieldChangeDto>()
            },
            new()
            {
                Timestamp = new DateTime(2024, 1, 2, 10, 0, 0),
                EventType = HistoryEventType.Updated,
                EntityType = "Environment",
                EntityIdentifier = "2",
                ChangedBy = "user@test.com",
                Changes = new List<FieldChangeDto>()
            },
            new()
            {
                Timestamp = new DateTime(2024, 1, 3, 10, 0, 0),
                EventType = HistoryEventType.Deleted,
                EntityType = "Role",
                EntityIdentifier = "3",
                ChangedBy = "superuser@test.com",
                Changes = new List<FieldChangeDto>()
            }
        };

        var cut = RenderHistoryTimeline(entries);

        // Apply search filter first
        await SetSearchBoxValue(cut, "SystemPermission");

        // Verify filter is applied (only 1 entry shown)
        await RenderAndAssert(cut, () =>
        {
            var changesDisplays = cut.FindComponents<HistoryChangesDisplay>();
            Assert.That(changesDisplays, Has.Count.EqualTo(1));
        });

        // Act - Click Reset Grid button
        await ClickResetGridButton(cut);

        // Assert - All entries should be displayed
        await RenderAndAssert(cut, () =>
        {
            var changesDisplays = cut.FindComponents<HistoryChangesDisplay>();
            Assert.That(changesDisplays, Has.Count.EqualTo(3));
        });
    }

    [Test]
    public async Task ResetGridButton_WhenClicked_ClearsSearchBoxValue()
    {
        // Arrange
        var entries = new List<HistoryEntryDto>
        {
            new()
            {
                Timestamp = new DateTime(2024, 1, 1, 10, 0, 0),
                EventType = HistoryEventType.Created,
                EntityType = "SystemPermission",
                EntityIdentifier = "1",
                ChangedBy = "admin@test.com",
                Changes = new List<FieldChangeDto>()
            }
        };

        var cut = RenderHistoryTimeline(entries);

        // Apply search filter first
        await SetSearchBoxValue(cut, "TestSearchValue");

        // Act - Click Reset Grid button
        await ClickResetGridButton(cut);

        // Assert - Search box should be cleared
        await RenderAndAssert(cut, () =>
        {
            var textBox = cut.FindComponent<TelerikTextBox>();
            Assert.That(textBox.Instance.Value, Is.Empty);
        });
    }

    [Test]
    public async Task ResetFiltersButton_WithNoFiltersApplied_DisplaysAllEntries()
    {
        // Arrange
        var entries = new List<HistoryEntryDto>
        {
            new()
            {
                Timestamp = new DateTime(2024, 1, 1, 10, 0, 0),
                EventType = HistoryEventType.Created,
                EntityType = "SystemPermission",
                EntityIdentifier = "1",
                ChangedBy = "admin@test.com",
                Changes = new List<FieldChangeDto>()
            },
            new()
            {
                Timestamp = new DateTime(2024, 1, 2, 10, 0, 0),
                EventType = HistoryEventType.Updated,
                EntityType = "Environment",
                EntityIdentifier = "2",
                ChangedBy = "user@test.com",
                Changes = new List<FieldChangeDto>()
            }
        };

        var cut = RenderHistoryTimeline(entries);

        // Act - Click Reset Filters button without applying any filters
        await ClickResetFiltersButton(cut);

        // Assert - All entries should still be displayed
        await RenderAndAssert(cut, () =>
        {
            var changesDisplays = cut.FindComponents<HistoryChangesDisplay>();
            Assert.That(changesDisplays, Has.Count.EqualTo(2));
        });
    }

    [Test]
    public async Task ResetGridButton_WithNoFiltersApplied_DisplaysAllEntries()
    {
        // Arrange
        var entries = new List<HistoryEntryDto>
        {
            new()
            {
                Timestamp = new DateTime(2024, 1, 1, 10, 0, 0),
                EventType = HistoryEventType.Created,
                EntityType = "SystemPermission",
                EntityIdentifier = "1",
                ChangedBy = "admin@test.com",
                Changes = new List<FieldChangeDto>()
            },
            new()
            {
                Timestamp = new DateTime(2024, 1, 2, 10, 0, 0),
                EventType = HistoryEventType.Updated,
                EntityType = "Environment",
                EntityIdentifier = "2",
                ChangedBy = "user@test.com",
                Changes = new List<FieldChangeDto>()
            }
        };

        var cut = RenderHistoryTimeline(entries);

        // Act - Click Reset Grid button without applying any filters
        await ClickResetGridButton(cut);

        // Assert - All entries should still be displayed
        await RenderAndAssert(cut, () =>
        {
            var changesDisplays = cut.FindComponents<HistoryChangesDisplay>();
            Assert.That(changesDisplays, Has.Count.EqualTo(2));
        });
    }

    private IRenderedComponent<TelerikRootComponent> RenderHistoryTimeline(List<HistoryEntryDto> entries)
    {
        return _ctx.RenderComponent<TelerikRootComponent>(parameters => parameters
            .AddChildContent<TestableHistoryTimeline>(childParameters => childParameters
                .Add(p => p.HistoryEntries, entries)));
    }

    private static async Task SetSearchBoxValue(
        IRenderedComponent<TelerikRootComponent> cut,
        string searchText)
    {
        var textBox = cut.FindComponent<TelerikTextBox>();
        textBox.SetParametersAndRender(parameters => parameters
            .Add(p => p.Value, searchText));
        await textBox.InvokeAsync(() =>
        {
            textBox.Instance.ValueChanged.InvokeAsync(searchText);
            textBox.Render();
        });
    }

    private static async Task ClickResetFiltersButton(IRenderedComponent<TelerikRootComponent> cut)
    {
        var buttons = cut.FindAll("button");
        var resetFiltersButton = buttons.First(b => b.TextContent.Contains("Reset all filters"));
        await cut.InvokeAsync(() => resetFiltersButton.Click());
    }

    private static async Task ClickResetGridButton(IRenderedComponent<TelerikRootComponent> cut)
    {
        var buttons = cut.FindAll("button");
        var resetGridButton = buttons.First(b => b.TextContent.Contains("Reset grid"));
        await cut.InvokeAsync(() => resetGridButton.Click());
    }

    private static async Task RenderAndAssert(
        IRenderedComponent<TelerikRootComponent> cut,
        Action assertion)
    {
        var testableTimeline = cut.FindComponent<TestableHistoryTimeline>();
        await testableTimeline.InvokeAsync(testableTimeline.Instance.InvokeStateHasChangedAsync);
        cut.WaitForAssertion(async () => { await Task.Delay(250).ContinueWith(_ => assertion()); }, _assertionTimeout);
    }
}

