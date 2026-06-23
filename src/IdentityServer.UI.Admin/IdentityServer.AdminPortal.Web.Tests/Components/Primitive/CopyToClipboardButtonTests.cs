// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

using AngleSharp.Dom;
using Bunit;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging;
using NSubstitute;
using NSubstitute.ExceptionExtensions;
using IdentityServer.AdminPortal.Web.Components.Interop;
using IdentityServer.AdminPortal.Web.Components.Primitive;
using IdentityServer.AdminPortal.Web.Services;
using TestContext = Bunit.TestContext;

namespace IdentityServer.AdminPortal.Web.Tests.Components.Primitive;

[TestFixture]
public class CopyToClipboardButtonTests
{
    [Test]
    public void RendersButton_WithDefaultClassAndIcon()
    {
        // Arrange
        using var ctx = new TestContext();
        var cbs = Substitute.For<IClipboardService>();
        ctx.Services.AddSingleton(cbs);
        ctx.Services.AddSingleton(Substitute.For<NotificationService>());
        ctx.Services.AddSingleton(Substitute.For<ILogger<CopyToClipboardButton>>());

        // Act
        var cut = ctx.RenderComponent<CopyToClipboardButton>(parameters => parameters
            .Add(p => p.ValueToCopy, "test value"));

        // Assert
        var btn = cut.Find("button");
        Assert.That(cut.Markup, Does.Contain("k-button-clear-secondary").And.Contain("k-svg-i-copy")); // simple way check
    }

    [Test]
    public void DoesNotCopy_WhenValueToCopyIsEmpty()
    {
        // Arrange
        using var ctx = new TestContext();
        var clipboardService = Substitute.For<IClipboardService>();
        ctx.Services.AddSingleton(clipboardService);
        ctx.Services.AddSingleton(Substitute.For<NotificationService>());
        ctx.Services.AddSingleton(Substitute.For<ILogger<CopyToClipboardButton>>());

        var cut = ctx.RenderComponent<CopyToClipboardButton>(parameters => parameters
            .Add(p => p.ValueToCopy, ""));

        // Act
        cut.Find("button").Click();

        // Assert
        clipboardService.DidNotReceive().CopyToClipboard(Arg.Any<string>());
    }

    [Test]
    public void CopiesToClipboard_WhenButtonClicked()
    {
        // Arrange
        using var ctx = new Bunit.TestContext();
        var clipboardService = SetupDependencies(ctx);
        var value = "copy me";
        var cut = ctx.RenderComponent<CopyToClipboardButton>(parameters => parameters
            .Add(p => p.ValueToCopy, value));

        // Act
        cut.Find("button").Click();

        // Assert
        clipboardService.Received(1).CopyToClipboard(value);
    }

    [Test]
    public async Task ChangesState_WhenCopyingSucceeds()
    {
        // Arrange
        using var ctx = new TestContext();
        var clipboardService = SetupDependencies(ctx);
        var value = "copy me";
        var cut = ctx.RenderComponent<CopyToClipboardButton>(parameters => parameters
            .Add(p => p.ValueToCopy, value));

        // Act
        cut.Find("button").Click();

        // Assert
        CheckMarkup(cut, "k-button-solid-success", "k-svg-i-check"); // changes to success state
        await Task.Delay(2300);
        CheckMarkup(cut, "k-button-clear-secondary", "k-svg-i-copy"); // ...and back to default after delay
    }

    [Test]
    public void ChangesState_WhenCopyingFails()
    {
        // Arrange
        using var ctx = new TestContext();
        var clipboardService = SetupDependencies(ctx);
        clipboardService.CopyToClipboard(Arg.Any<string>()).ThrowsAsync<ArgumentException>();
        var value = "copy me";
        var cut = ctx.RenderComponent<CopyToClipboardButton>(parameters => parameters
            .Add(p => p.ValueToCopy, value));

        // Act
        cut.Find("button").Click();

        // Assert
        CheckMarkup(cut, "k-button-solid-error", "k-svg-i-x-circle");
    }

    private static void CheckMarkup(IRenderedComponent<CopyToClipboardButton> cut, string btnStyleSelector, string spanStyleSelector)
    {
        IElement btn = cut.Find($"button.{btnStyleSelector}.k-icon-button.tooltip-target");
        _ = cut.Find($"span.k-svg-icon.{spanStyleSelector}");
        btn.MarkupMatches("<button diff:ignoreAttributes><span diff:ignoreAttributes><svg diff:ignore /></span></button>");
    }

    private static IClipboardService SetupDependencies(TestContext ctx)
    {
        var clipboardService = Substitute.For<IClipboardService>();
        ctx.Services.AddSingleton(clipboardService);
        ctx.Services.AddSingleton(Substitute.For<NotificationService>());
        ctx.Services.AddSingleton(Substitute.For<ILogger<CopyToClipboardButton>>());

        return clipboardService;
    }
}
