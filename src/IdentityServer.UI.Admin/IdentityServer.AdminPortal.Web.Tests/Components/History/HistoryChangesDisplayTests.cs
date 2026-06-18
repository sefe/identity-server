using Bunit;
using IdentityServer.Abstraction.DTO.History;
using IdentityServer.Abstraction.Enums;
using IdentityServer.AdminPortal.Web.Components.History;

namespace IdentityServer.AdminPortal.Web.Tests.Components.History;

public class HistoryChangesDisplayTests : Bunit.TestContext
{
    [Test]
    public void RendersNoFieldChangesMessage_WhenChangesIsNull()
    {
        // Arrange & Act
        var cut = RenderComponent<HistoryChangesDisplay>(parameters => parameters
            .Add(p => p.Changes, null));

        // Assert
        var messageSpan = cut.Find("span.text-muted");
        Assert.That(messageSpan.TextContent, Is.EqualTo("No field changes"));
    }

    [Test]
    public void RendersNoFieldChangesMessage_WhenChangesIsEmpty()
    {
        // Arrange & Act
        var cut = RenderComponent<HistoryChangesDisplay>(parameters => parameters
            .Add(p => p.Changes, new List<FieldChangeDto>()));

        // Assert
        var messageSpan = cut.Find("span.text-muted");
        Assert.That(messageSpan.TextContent, Is.EqualTo("No field changes"));
    }

    [Test]
    public void RendersDeletedEvent_WithOldValue()
    {
        // Arrange
        var changes = new List<FieldChangeDto>
        {
            new() { FieldName = "Username", OldValue = "john.doe" }
        };

        // Act
        var cut = RenderComponent<HistoryChangesDisplay>(parameters => parameters
            .Add(p => p.Changes, changes)
            .Add(p => p.EventType, HistoryEventType.Deleted));

        // Assert
        var container = cut.Find(".field-changes");
        var changeItem = container.QuerySelector(".mb-1");
        Assert.That(changeItem, Is.Not.Null);

        var fieldName = changeItem.QuerySelector("strong");
        var oldValue = changeItem.QuerySelector("span.text-danger");

        using (Assert.EnterMultipleScope())
        {
            Assert.That(fieldName?.TextContent, Is.EqualTo("Username: "));
            Assert.That(oldValue?.TextContent, Is.EqualTo("john.doe"));
            Assert.That(changeItem.TextContent, Does.Not.Contain("→"));
        }
    }

    [Test]
    public void RendersDeletedEvent_WithEmptyOldValue()
    {
        // Arrange
        var changes = new List<FieldChangeDto>
        {
            new() { FieldName = "Email", OldValue = "" }
        };

        // Act
        var cut = RenderComponent<HistoryChangesDisplay>(parameters => parameters
            .Add(p => p.Changes, changes)
            .Add(p => p.EventType, HistoryEventType.Deleted));

        // Assert
        var container = cut.Find(".field-changes");
        var changeItem = container.QuerySelector(".mb-1");
        var fieldName = changeItem.QuerySelector("strong");
        var emptyValue = changeItem.QuerySelector("span.text-muted.fst-italic");
        using (Assert.EnterMultipleScope())
        {
            Assert.That(fieldName?.TextContent, Is.EqualTo("Email: "));
            Assert.That(emptyValue?.TextContent, Is.EqualTo("(empty)"));
        }
    }

    [Test]
    public void RendersNonDeletedEvent_WithOldAndNewValues()
    {
        // Arrange
        var changes = new List<FieldChangeDto>
        {
            new() { FieldName = "Status", OldValue = "Active", NewValue = "Inactive" }
        };

        // Act
        var cut = RenderComponent<HistoryChangesDisplay>(parameters => parameters
            .Add(p => p.Changes, changes)
            .Add(p => p.EventType, HistoryEventType.Updated));

        // Assert
        var container = cut.Find(".field-changes");
        var changeItem = container.QuerySelector(".mb-1");
        var fieldName = changeItem.QuerySelector("strong");
        var oldValue = changeItem.QuerySelector("span.text-decoration-line-through.text-danger");
        var newValue = changeItem.QuerySelector("span.fw-bold.text-success");

        using (Assert.EnterMultipleScope())
        {
            Assert.That(fieldName?.TextContent, Is.EqualTo("Status: "));
            Assert.That(oldValue?.TextContent, Is.EqualTo("Active"));
            Assert.That(newValue?.TextContent, Is.EqualTo("Inactive"));
            Assert.That(changeItem.TextContent, Does.Contain("→"));
        }
    }

    [Test]
    public void RendersNonDeletedEvent_WithOnlyNewValue()
    {
        // Arrange
        var changes = new List<FieldChangeDto>
        {
            new() { FieldName = "Phone", OldValue = null, NewValue = "123-456-7890" }
        };

        // Act
        var cut = RenderComponent<HistoryChangesDisplay>(parameters => parameters
            .Add(p => p.Changes, changes)
            .Add(p => p.EventType, HistoryEventType.Created));

        // Assert
        var container = cut.Find(".field-changes");
        var changeItem = container.QuerySelector(".mb-1");
        var fieldName = changeItem.QuerySelector("strong");
        var newValue = changeItem.QuerySelector("span.fw-bold.text-success");
        // Should not show old value or arrow when only new value exists
        var oldValue = changeItem.QuerySelector("span.text-decoration-line-through");

        using (Assert.EnterMultipleScope())
        {
            Assert.That(fieldName?.TextContent, Is.EqualTo("Phone: "));
            Assert.That(newValue?.TextContent, Is.EqualTo("123-456-7890"));
            Assert.That(oldValue, Is.Null);
            Assert.That(changeItem.TextContent, Does.Not.Contain("→"));
        }
    }

    [Test]
    public void RendersNonDeletedEvent_WithEmptyNewValue()
    {
        // Arrange
        var changes = new List<FieldChangeDto>
        {
            new() { FieldName = "Description", OldValue = "Old desc", NewValue = "" }
        };

        // Act
        var cut = RenderComponent<HistoryChangesDisplay>(parameters => parameters
            .Add(p => p.Changes, changes)
            .Add(p => p.EventType, HistoryEventType.Updated));

        // Assert
        var container = cut.Find(".field-changes");
        var changeItem = container.QuerySelector(".mb-1");
        var fieldName = changeItem.QuerySelector("strong");
        var oldValue = changeItem.QuerySelector("span.text-decoration-line-through.text-danger");
        var emptyValue = changeItem.QuerySelector("span.text-muted.fst-italic");

        using (Assert.EnterMultipleScope())
        {
            Assert.That(fieldName?.TextContent, Is.EqualTo("Description: "));
            Assert.That(oldValue?.TextContent, Is.EqualTo("Old desc"));
            Assert.That(emptyValue?.TextContent, Is.EqualTo("(empty)"));
            Assert.That(changeItem.TextContent, Does.Contain("→"));
        }
    }

    [Test]
    public void RendersMultipleFieldChanges()
    {
        // Arrange
        var changes = new List<FieldChangeDto>
        {
            new() { FieldName = "Name", OldValue = "John", NewValue = "Jane" },
            new() { FieldName = "Age", OldValue = "30", NewValue = "31" },
            new() { FieldName = "City", OldValue = "NYC", NewValue = "LA" }
        };

        // Act
        var cut = RenderComponent<HistoryChangesDisplay>(parameters => parameters
            .Add(p => p.Changes, changes)
            .Add(p => p.EventType, HistoryEventType.Updated));

        // Assert
        var container = cut.Find(".field-changes");
        var changeItems = container.QuerySelectorAll(".mb-1");
        Assert.That(changeItems, Has.Length.EqualTo(3));

        // Verify first change (Name)
        var nameField = changeItems[0].QuerySelector("strong");
        Assert.That(nameField?.TextContent, Is.EqualTo("Name: "));
        var nameOld = changeItems[0].QuerySelector("span.text-decoration-line-through.text-danger");
        Assert.That(nameOld?.TextContent, Is.EqualTo("John"));
        var nameNew = changeItems[0].QuerySelector("span.fw-bold.text-success");
        Assert.That(nameNew?.TextContent, Is.EqualTo("Jane"));

        // Verify second change (Age)
        var ageField = changeItems[1].QuerySelector("strong");
        Assert.That(ageField?.TextContent, Is.EqualTo("Age: "));
        var ageOld = changeItems[1].QuerySelector("span.text-decoration-line-through.text-danger");
        Assert.That(ageOld?.TextContent, Is.EqualTo("30"));
        var ageNew = changeItems[1].QuerySelector("span.fw-bold.text-success");
        Assert.That(ageNew?.TextContent, Is.EqualTo("31"));

        // Verify third change (City)
        var cityField = changeItems[2].QuerySelector("strong");
        Assert.That(cityField?.TextContent, Is.EqualTo("City: "));
        var cityOld = changeItems[2].QuerySelector("span.text-decoration-line-through.text-danger");
        Assert.That(cityOld?.TextContent, Is.EqualTo("NYC"));
        var cityNew = changeItems[2].QuerySelector("span.fw-bold.text-success");
        Assert.That(cityNew?.TextContent, Is.EqualTo("LA"));
    }

    [Test]
    public void RendersFieldChangesContainer_WhenChangesExist()
    {
        // Arrange
        var changes = new List<FieldChangeDto>
        {
            new() { FieldName = "Test", OldValue = "A", NewValue = "B" }
        };

        // Act
        var cut = RenderComponent<HistoryChangesDisplay>(parameters => parameters
            .Add(p => p.Changes, changes));

        // Assert
        Assert.That(cut.Find(".field-changes"), Is.Not.Null);
    }
}
