// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

using Bunit;
using IdentityServer.AdminPortal.Web.Components.Primitive.Banner;
using TestContext = Bunit.TestContext;

namespace IdentityServer.AdminPortal.Web.Tests.Components.Primitive.Banner;

[TestFixture]
public class BannerSecretNoExpirationTests
{
    [Test]
    public void CalculatesFilteredSecretsCount_WithNoExpiration()
    {
        // Arrange
        using var ctx = new TestContext();

        var secrets = new List<TestSecret>
        {
            new() { Expiration = null }, // no expiration
            new() { Expiration = null }, // no expiration
            new() { Expiration = DateTime.UtcNow.AddDays(30) }, // has expiration
            new() { Expiration = DateTime.UtcNow.AddYears(1) }  // has expiration
        };

        // Act
        var cut = ctx.RenderComponent<BannerSecretNoExpiration>(parameters => parameters
            .Add(p => p.Secrets, secrets));

        // Assert
        Assert.That(cut.Markup, Does.Contain("2 secrets exist"));
    }

    [Test]
    public void DisplaysBanner_WhenSecretsWithoutExpiration()
    {
        // Arrange
        using var ctx = new TestContext();

        var secrets = new List<TestSecret>
        {
            new() { Expiration = null }
        };

        // Act
        var cut = ctx.RenderComponent<BannerSecretNoExpiration>(parameters => parameters
            .Add(p => p.Secrets, secrets));

        // Assert
        Assert.That(cut.Markup, Does.Contain("Secrets Without Expiration"));
        Assert.That(cut.Markup, Does.Contain("1 secret exists"));
        Assert.That(cut.Markup, Does.Contain("without expiration and should be rotated"));
    }

    [Test]
    public void UsesCorrectPluralForm_WithMultipleSecrets()
    {
        // Arrange
        using var ctx = new TestContext();

        var secrets = new List<TestSecret>
        {
            new() { Expiration = null },
            new() { Expiration = null },
            new() { Expiration = null }
        };

        // Act
        var cut = ctx.RenderComponent<BannerSecretNoExpiration>(parameters => parameters
            .Add(p => p.Secrets, secrets));

        // Assert
        Assert.That(cut.Markup, Does.Contain("3 secrets exist"));
    }

    [Test]
    public void UsesCorrectSingularForm_WithOneSecret()
    {
        // Arrange
        using var ctx = new TestContext();

        var secrets = new List<TestSecret>
        {
            new() { Expiration = null }
        };

        // Act
        var cut = ctx.RenderComponent<BannerSecretNoExpiration>(parameters => parameters
            .Add(p => p.Secrets, secrets));

        // Assert
        Assert.That(cut.Markup, Does.Contain("1 secret exists"));
    }

    [Test]
    public void HidesBanner_WhenDismissed()
    {
        // Arrange
        using var ctx = new TestContext();

        var secrets = new List<TestSecret>
        {
            new() { Expiration = null }
        };

        var cut = ctx.RenderComponent<BannerSecretNoExpiration>(parameters => parameters
            .Add(p => p.Secrets, secrets));

        // Act
        var dismissButton = cut.Find("button.btn-close");
        dismissButton.Click();

        // Assert
        Assert.That(cut.Markup, Does.Not.Contain("Secrets Without Expiration"));
    }

    [Test]
    public void DoesNotDisplayBanner_WhenAllSecretsHaveExpiration()
    {
        // Arrange
        using var ctx = new TestContext();

        var secrets = new List<TestSecret>
        {
            new() { Expiration = DateTime.UtcNow.AddDays(30) },
            new() { Expiration = DateTime.UtcNow.AddYears(1) },
            new() { Expiration = DateTime.UtcNow.AddDays(-10) } // expired but has expiration
        };

        // Act
        var cut = ctx.RenderComponent<BannerSecretNoExpiration>(parameters => parameters
            .Add(p => p.Secrets, secrets));

        // Assert
        Assert.That(cut.Markup, Does.Not.Contain("Secrets Without Expiration"));
    }

    [Test]
    public void DoesNotDisplayBanner_WhenNoSecrets()
    {
        // Arrange
        using var ctx = new TestContext();

        var secrets = new List<TestSecret>();

        // Act
        var cut = ctx.RenderComponent<BannerSecretNoExpiration>(parameters => parameters
            .Add(p => p.Secrets, secrets));

        // Assert
        Assert.That(cut.Markup, Does.Not.Contain("Secrets Without Expiration"));
    }

    [Test]
    public void CountsOnlyNullExpirations_IgnoringExpiredSecrets()
    {
        // Arrange
        using var ctx = new TestContext();

        var secrets = new List<TestSecret>
        {
            new() { Expiration = null },
            new() { Expiration = DateTime.UtcNow.AddDays(-100) }, // expired but has expiration date
            new() { Expiration = DateTime.UtcNow.AddDays(10) }
        };

        // Act
        var cut = ctx.RenderComponent<BannerSecretNoExpiration>(parameters => parameters
            .Add(p => p.Secrets, secrets));

        // Assert
        Assert.That(cut.Markup, Does.Contain("1 secret exists"));
    }
}
