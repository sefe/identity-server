// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

using Bunit;
using IdentityServer.AdminPortal.Web.Components.Primitive;
using TestContext = Bunit.TestContext;

namespace IdentityServer.AdminPortal.Web.Tests.Components.Primitive;

[TestFixture]
public class ErrorAlertTests
{
    [Test]
    public void ErrorAlert_WithNullErrorMessage_DoesNotRenderAlert()
    {
        // Arrange & Act
        using var ctx = new TestContext();
        var cut = ctx.RenderComponent<ErrorAlert>(parameters => parameters
            .Add(p => p.ErrorMessage, null));

        // Assert
        Assert.That(cut.Markup, Is.Empty);
    }

    [Test]
    public void ErrorAlert_WithEmptyErrorMessage_DoesNotRenderAlert()
    {
        // Arrange & Act
        using var ctx = new TestContext();
        var cut = ctx.RenderComponent<ErrorAlert>(parameters => parameters
            .Add(p => p.ErrorMessage, string.Empty));

        // Assert
        Assert.That(cut.Markup, Is.Empty);
    }

    [Test]
    public void ErrorAlert_WithWhitespaceErrorMessage_DoesNotRenderAlert()
    {
        // Arrange & Act
        using var ctx = new TestContext();
        var cut = ctx.RenderComponent<ErrorAlert>(parameters => parameters
            .Add(p => p.ErrorMessage, "   "));

        // Assert
        Assert.That(cut.Markup, Is.Empty);
    }

    [Test]
    public void ErrorAlert_WithValidErrorMessage_RendersAlertWithErrorText()
    {
        // Arrange
        const string errorMessage = "An error occurred";

        // Act
        using var ctx = new TestContext();
        var cut = ctx.RenderComponent<ErrorAlert>(parameters => parameters
            .Add(p => p.ErrorMessage, errorMessage));

        // Assert
        using (Assert.EnterMultipleScope())
        {
            var alertDiv = cut.Find("div.alert.alert-danger");
            Assert.That(alertDiv, Is.Not.Null);
            Assert.That(alertDiv.InnerHtml, Does.Contain("<strong>Error!</strong>"));
            Assert.That(alertDiv.InnerHtml, Does.Contain(errorMessage));
        }
    }

    [Test]
    public void ErrorAlert_WithDefaultCssClass_AppliesMb1Class()
    {
        // Arrange
        const string errorMessage = "Test error";

        // Act
        using var ctx = new TestContext();
        var cut = ctx.RenderComponent<ErrorAlert>(parameters => parameters
            .Add(p => p.ErrorMessage, errorMessage));

        // Assert
        var alertDiv = cut.Find("div.alert");
        Assert.That(alertDiv.ClassList, Does.Contain("mb-1"));
    }

    [Test]
    public void ErrorAlert_WithCustomCssClass_AppliesCustomClass()
    {
        // Arrange
        const string errorMessage = "Test error";
        const string customClass = "mt-3 mb-2";

        // Act
        using var ctx = new TestContext();
        var cut = ctx.RenderComponent<ErrorAlert>(parameters => parameters
            .Add(p => p.ErrorMessage, errorMessage)
            .Add(p => p.CssClass, customClass));

        // Assert
        var alertDiv = cut.Find("div.alert");
        Assert.That(alertDiv.ClassName, Does.Contain(customClass));
    }

    [Test]
    public void ErrorAlert_WithEmptyCssClass_DoesNotApplyExtraClasses()
    {
        // Arrange
        const string errorMessage = "Test error";

        // Act
        using var ctx = new TestContext();
        var cut = ctx.RenderComponent<ErrorAlert>(parameters => parameters
            .Add(p => p.ErrorMessage, errorMessage)
            .Add(p => p.CssClass, string.Empty));

        // Assert
        using (Assert.EnterMultipleScope())
        {
            var alertDiv = cut.Find("div.alert");
            Assert.That(alertDiv.ClassList, Does.Contain("alert"));
            Assert.That(alertDiv.ClassList, Does.Contain("alert-danger"));
            Assert.That(alertDiv.ClassList, Does.Not.Contain("mb-1"));
        }
    }

    [Test]
    public void ErrorAlert_WithLongErrorMessage_RendersFullMessage()
    {
        // Arrange
        const string longErrorMessage = "This is a very long error message that contains multiple words and should be displayed in its entirety to the user so they understand what went wrong.";

        // Act
        using var ctx = new TestContext();
        var cut = ctx.RenderComponent<ErrorAlert>(parameters => parameters
            .Add(p => p.ErrorMessage, longErrorMessage));

        // Assert
        var alertDiv = cut.Find("div.alert");
        Assert.That(alertDiv.InnerHtml, Does.Contain(longErrorMessage));
    }

    [Test]
    public void ErrorAlert_WithSpecialCharactersInMessage_RendersCorrectly()
    {
        // Arrange
        const string errorWithSpecialChars = "Error: <value> & \"quoted\" text";

        // Act
        using var ctx = new TestContext();
        var cut = ctx.RenderComponent<ErrorAlert>(parameters => parameters
            .Add(p => p.ErrorMessage, errorWithSpecialChars));

        // Assert
        var alertDiv = cut.Find("div.alert");
        Assert.That(alertDiv.TextContent, Does.Contain(errorWithSpecialChars));
    }

    [Test]
    public void ErrorAlert_HasCorrectBootstrapClasses()
    {
        // Arrange
        const string errorMessage = "Test error";

        // Act
        using var ctx = new TestContext();
        var cut = ctx.RenderComponent<ErrorAlert>(parameters => parameters
            .Add(p => p.ErrorMessage, errorMessage));

        // Assert
        using (Assert.EnterMultipleScope())
        {
            var alertDiv = cut.Find("div");
            Assert.That(alertDiv.ClassList, Does.Contain("alert"));
            Assert.That(alertDiv.ClassList, Does.Contain("alert-danger"));
            Assert.That(alertDiv.ClassList, Does.Contain("alert-dismissible"));
        }
    }

    [Test]
    public void ErrorAlert_UpdatedErrorMessage_RendersNewMessage()
    {
        // Arrange
        const string initialMessage = "Initial error";
        const string updatedMessage = "Updated error";

        using var ctx = new TestContext();
        var cut = ctx.RenderComponent<ErrorAlert>(parameters => parameters
            .Add(p => p.ErrorMessage, initialMessage));

        // Act
        cut.SetParametersAndRender(parameters => parameters
            .Add(p => p.ErrorMessage, updatedMessage));

        // Assert
        using (Assert.EnterMultipleScope())
        {
            var alertDiv = cut.Find("div.alert");
            Assert.That(alertDiv.TextContent, Does.Contain(updatedMessage));
            Assert.That(alertDiv.TextContent, Does.Not.Contain(initialMessage));
        }
    }

    [Test]
    public void ErrorAlert_ChangedFromErrorToNull_HidesAlert()
    {
        // Arrange
        const string initialMessage = "Initial error";

        using var ctx = new TestContext();
        var cut = ctx.RenderComponent<ErrorAlert>(parameters => parameters
            .Add(p => p.ErrorMessage, initialMessage));

        // Act
        cut.SetParametersAndRender(parameters => parameters
            .Add(p => p.ErrorMessage, null));

        // Assert
        Assert.That(cut.Markup, Is.Empty);
    }

    [Test]
    public void ErrorAlert_RendersCloseButton()
    {
        // Arrange
        const string errorMessage = "Test error";

        // Act
        using var ctx = new TestContext();
        var cut = ctx.RenderComponent<ErrorAlert>(parameters => parameters
            .Add(p => p.ErrorMessage, errorMessage));

        // Assert
        using (Assert.EnterMultipleScope())
        {
            var alertDiv = cut.Find("div.alert");
            Assert.That(alertDiv.ClassList, Does.Contain("alert-dismissible"));
            Assert.That(alertDiv.ClassList, Does.Contain("fade"));
            Assert.That(alertDiv.ClassList, Does.Contain("show"));

            var closeButton = cut.Find("button.btn-close");
            Assert.That(closeButton, Is.Not.Null);
            Assert.That(closeButton.GetAttribute("aria-label"), Is.EqualTo("Close"));
        }
    }

    [Test]
    public void ErrorAlert_WhenDismissButtonClicked_InvokesErrorMessageChangedWithNull()
    {
        // Arrange
        const string errorMessage = "Test error";
        string capturedValue = errorMessage;

        using var ctx = new TestContext();
        var cut = ctx.RenderComponent<ErrorAlert>(parameters => parameters
            .Add(p => p.ErrorMessage, errorMessage)
            .Add(p => p.ErrorMessageChanged, newValue => { capturedValue = newValue; }));

        // Act
        var closeButton = cut.Find("button.btn-close");
        closeButton.Click();

        // Assert
        Assert.That(capturedValue, Is.Null);
    }

    [Test]
    public void ErrorAlert_WhenDismissButtonClickedWithoutCallback_DoesNotThrow()
    {
        // Arrange
        const string errorMessage = "Test error";

        using var ctx = new TestContext();
        var cut = ctx.RenderComponent<ErrorAlert>(parameters => parameters
            .Add(p => p.ErrorMessage, errorMessage));

        // Act & Assert - Should not throw
        var closeButton = cut.Find("button.btn-close");
        Assert.DoesNotThrow(() => closeButton.Click());
    }

    [Test]
    public void ErrorAlert_WithTwoWayBinding_ClearsErrorMessageOnDismiss()
    {
        // Arrange
        string errorMessage = "Test error";

        using var ctx = new TestContext();
        var cut = ctx.RenderComponent<ErrorAlert>(parameters => parameters
            .Add(p => p.ErrorMessage, errorMessage)
            .Add(p => p.ErrorMessageChanged, newValue => { errorMessage = newValue; }));

        using (Assert.EnterMultipleScope())
        {
            Assert.That(cut.Markup, Is.Not.Empty, "Alert should be visible initially");
            Assert.That(errorMessage, Is.Not.Null, "Error message should not be null initially");
        }

        // Act
        var closeButton = cut.Find("button.btn-close");
        closeButton.Click();

        // Assert
        Assert.That(errorMessage, Is.Null, "Error message should be null after dismiss");
    }

    [Test]
    public void ErrorAlert_WithTwoWayBinding_AutomaticallyHidesAfterDismiss()
    {
        // Arrange
        string errorMessage = "Test error";

        using var ctx = new TestContext();
        var cut = ctx.RenderComponent<ErrorAlert>(parameters => parameters
            .Add(p => p.ErrorMessage, errorMessage)
            .Add(p => p.ErrorMessageChanged, newValue => { errorMessage = newValue; }));

        Assert.That(cut.Markup, Is.Not.Empty, "Alert should be visible initially");

        // Act - Click dismiss button
        var closeButton = cut.Find("button.btn-close");
        closeButton.Click();

        // Re-render with updated error message
        cut.SetParametersAndRender(parameters => parameters
            .Add(p => p.ErrorMessage, errorMessage));

        // Assert
        Assert.That(cut.Markup, Is.Empty, "Alert should be hidden after dismiss and re-render");
    }

    [Test]
    public void ErrorAlert_WithRoleAttribute_HasCorrectAccessibility()
    {
        // Arrange
        const string errorMessage = "Test error";

        // Act
        using var ctx = new TestContext();
        var cut = ctx.RenderComponent<ErrorAlert>(parameters => parameters
            .Add(p => p.ErrorMessage, errorMessage));

        // Assert
        var alertDiv = cut.Find("div.alert");
        Assert.That(alertDiv.GetAttribute("role"), Is.EqualTo("alert"));
    }

    [Test]
    public void ErrorAlert_UsingBindSyntax_WorksCorrectly()
    {
        // Arrange
        string errorMessage = "Initial error";

        using var ctx = new TestContext();

        // Simulate @bind-ErrorMessage syntax by setting both parameters
        var cut = ctx.RenderComponent<ErrorAlert>(parameters => parameters
            .Add(p => p.ErrorMessage, errorMessage)
            .Add(p => p.ErrorMessageChanged, newValue => { errorMessage = newValue; }));

        // Verify initial state
        Assert.That(cut.Markup, Does.Contain("Initial error"));

        // Act - Dismiss the alert
        var closeButton = cut.Find("button.btn-close");
        closeButton.Click();

        // Assert - Error message should be cleared
        using (Assert.EnterMultipleScope())
        {
            Assert.That(errorMessage, Is.Null, "Bound error message should be null");

            // Re-render with new value
            cut.SetParametersAndRender(parameters => parameters
                .Add(p => p.ErrorMessage, errorMessage));

            Assert.That(cut.Markup, Is.Empty, "Alert should not render when error message is null");
        }
    }
}
