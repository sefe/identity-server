using Bunit;
using Microsoft.AspNetCore.Components;
using Telerik.Blazor.Components;
using IdentityServer.Abstraction.DTO.History;
using IdentityServer.Abstraction.Enums;
using IdentityServer.AdminPortal.Web.Components.History;
using IdentityServer.AdminPortal.Web.Services.History;

namespace IdentityServer.AdminPortal.Web.Tests.Components.History;

[TestFixture]
public class UndoConfirmationDialogTests
{
    private Bunit.TestContext _ctx;

    [SetUp]
    public void Setup()
    {
        _ctx = new Bunit.TestContext();
        _ctx.JSInterop.Mode = JSRuntimeMode.Loose;
    }

    [TearDown]
    public void TearDown()
    {
        _ctx?.Dispose();
    }

    [Test]
    public void Dialog_WhenNotVisible_DoesNotRenderContent()
    {
        // Arrange & Act
        var cut = RenderDialog(isVisible: false);

        // Assert
        var dialogs = cut.FindAll("[class*='k-dialog']");
        Assert.That(dialogs, Has.Count.EqualTo(0));
    }

    [Test]
    public void Dialog_WhenVisible_RendersDialogTitle()
    {
        // Arrange
        var entry = CreateTestHistoryEntry(HistoryEventType.Updated);
        var preview = CreateTestUndoPreview();

        // Act
        var cut = RenderDialog(isVisible: true, entry: entry, undoPreview: preview);

        // Assert
        var title = cut.Find("[class*='k-dialog-title']");
        Assert.That(title.TextContent, Does.Contain("Undo this change"));
    }

    [Test]
    public void Dialog_WithChangesToReverse_DisplaysFieldChanges()
    {
        // Arrange
        var entry = CreateTestHistoryEntry(HistoryEventType.Updated);
        var preview = new UndoPreview
        {
            ChangesToReverse = new List<FieldChangeDto>
            {
                new() { FieldName = "ClientName", OldValue = "NewName", NewValue = "OldName" }
            },
        };

        // Act
        var cut = RenderDialog(isVisible: true, entry: entry, undoPreview: preview);

        // Assert
        var content = cut.Markup;
        using (Assert.EnterMultipleScope())
        {
            Assert.That(content, Does.Contain("ClientName"));
            Assert.That(content, Does.Contain("OldName"));
        }
    }

    [Test]
    public void Dialog_WithDeletedEntry_DisplaysRecreationInfo()
    {
        // Arrange
        var entry = CreateTestHistoryEntry(HistoryEventType.Deleted, "ClientRedirectUri");
        var preview = new UndoPreview
        {
            ChangesToReverse = new List<FieldChangeDto>
            {
                new() { FieldName = "RedirectUri", OldValue = null, NewValue = "https://example.com" }
            }
        };

        // Act
        var cut = RenderDialog(isVisible: true, entry: entry, undoPreview: preview);

        // Assert
        var infoAlert = cut.Find(".alert-info");
        Assert.That(infoAlert.TextContent, Does.Contain("recreate"));
    }

    [Test]
    public void Dialog_WhenLoading_DisablesButtons()
    {
        // Arrange
        var entry = CreateTestHistoryEntry(HistoryEventType.Updated);
        var preview = CreateTestUndoPreview();

        // Act
        var cut = RenderDialog(isVisible: true, entry: entry, undoPreview: preview, isLoading: true);

        // Assert
        var buttons = cut.FindAll("button");
        using (Assert.EnterMultipleScope())
        {
            Assert.That(buttons.All(b => b.HasAttribute("disabled")), Is.True);
        }
    }

    [Test]
    public void Dialog_WhenNoChangesToReverse_DisablesConfirmButton()
    {
        // Arrange
        var entry = CreateTestHistoryEntry(HistoryEventType.Updated);
        var preview = new UndoPreview
        {
            ChangesToReverse = new List<FieldChangeDto>(),
        };

        // Act
        var cut = RenderDialog(isVisible: true, entry: entry, undoPreview: preview);

        // Assert
        var buttons = cut.FindAll("button");
        var confirmButton = buttons.FirstOrDefault(b => b.TextContent.Contains("Confirm"));
        Assert.That(confirmButton?.HasAttribute("disabled"), Is.True);
    }

    [Test]
    public async Task Dialog_WhenCancelClicked_InvokesCancelCallback()
    {
        // Arrange
        var entry = CreateTestHistoryEntry(HistoryEventType.Updated);
        var preview = CreateTestUndoPreview();
        var cancelCalled = false;

        var cut = _ctx.RenderComponent<TelerikRootComponent>(parameters => parameters
            .AddChildContent<UndoConfirmationDialog>(childParams => childParams
                .Add(p => p.IsVisible, true)
                .Add(p => p.Entry, entry)
                .Add(p => p.UndoPreview, preview)
                .Add(p => p.OnCancel, EventCallback.Factory.Create(this, () => cancelCalled = true))));

        // Act
        var cancelButton = cut.FindAll("button").First(b => b.TextContent.Contains("Cancel"));
        await cut.InvokeAsync(() => cancelButton.Click());

        // Assert
        Assert.That(cancelCalled, Is.True);
    }

    [Test]
    public async Task Dialog_WhenConfirmClicked_InvokesConfirmCallback()
    {
        // Arrange
        var entry = CreateTestHistoryEntry(HistoryEventType.Updated);
        var preview = CreateTestUndoPreview();
        var confirmCalled = false;

        var cut = _ctx.RenderComponent<TelerikRootComponent>(parameters => parameters
            .AddChildContent<UndoConfirmationDialog>(childParams => childParams
                .Add(p => p.IsVisible, true)
                .Add(p => p.Entry, entry)
                .Add(p => p.UndoPreview, preview)
                .Add(p => p.OnConfirm, EventCallback.Factory.Create(this, () => confirmCalled = true))));

        // Act
        var confirmButton = cut.FindAll("button").First(b => b.TextContent.Contains("Confirm"));
        await cut.InvokeAsync(() => confirmButton.Click());

        // Assert
        Assert.That(confirmCalled, Is.True);
    }

    #region Helper Methods

    private IRenderedComponent<TelerikRootComponent> RenderDialog(
        bool isVisible = true,
        HistoryEntryDto entry = null!,
        UndoPreview undoPreview = null!,
        bool isLoading = false)
    {
        return _ctx.RenderComponent<TelerikRootComponent>(parameters => parameters
            .AddChildContent<UndoConfirmationDialog>(childParams => childParams
                .Add(p => p.IsVisible, isVisible)
                .Add(p => p.Entry, entry)
                .Add(p => p.UndoPreview, undoPreview)
                .Add(p => p.IsLoading, isLoading)));
    }

    private static HistoryEntryDto CreateTestHistoryEntry(HistoryEventType eventType, string entityType = "Client")
    {
        return new HistoryEntryDto
        {
            Timestamp = DateTime.UtcNow,
            EventType = eventType,
            EntityType = entityType,
            EntityIdentifier = "test-1",
            ChangedBy = "test@example.com",
            Changes = new List<FieldChangeDto>()
        };
    }

    private static UndoPreview CreateTestUndoPreview()
    {
        return new UndoPreview
        {
            ChangesToReverse = new List<FieldChangeDto>
            {
                new() { FieldName = "TestField", OldValue = "Old", NewValue = "New" }
            },
        };
    }

    #endregion
}
