// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

using Bunit;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Options;
using IdentityServer.Abstraction.Configs;
using IdentityServer.AdminPortal.Web.Components.Primitive.Banner;
using TestContext = Bunit.TestContext;

namespace IdentityServer.AdminPortal.Web.Tests.Components.Primitive.Banner;

[TestFixture]
public class BannerSecretExpiringTests
{
    [Test]
    public void CalculatesFilteredSecretsCount_WithExpiringSoon()
    {
        // Arrange
        using var ctx = new TestContext();
        var config = Options.Create(new SecretExpirationConfig { MaxValidityYears = 3, DaysBeforeExpirationNotification = 60 });
        ctx.Services.AddSingleton(config);

        var secrets = new List<TestSecret>
        {
            new() { Expiration = DateTime.UtcNow.AddDays(30) }, // expiring soon
            new() { Expiration = DateTime.UtcNow.AddDays(45) }, // expiring soon
            new() { Expiration = DateTime.UtcNow.AddDays(90) }, // not expiring soon
            new() { Expiration = null } // no expiration
        };

        // Act
        var cut = ctx.RenderComponent<BannerSecretExpiring>(parameters => parameters
            .Add(p => p.Secrets, secrets));

        // Assert
        Assert.That(cut.Markup, Does.Contain("2 secrets"));
    }

    [Test]
    public void DisplaysBanner_WhenSecretsExpiringSoon()
    {
        // Arrange
        using var ctx = new TestContext();
        var config = Options.Create(new SecretExpirationConfig { MaxValidityYears = 3, DaysBeforeExpirationNotification = 60 });
        ctx.Services.AddSingleton(config);

        var secrets = new List<TestSecret>
        {
            new() { Expiration = DateTime.UtcNow.AddDays(30) }
        };

        // Act
        var cut = ctx.RenderComponent<BannerSecretExpiring>(parameters => parameters
            .Add(p => p.Secrets, secrets));

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(cut.Markup, Does.Contain("Secrets Expiring Soon"));
            Assert.That(cut.Markup, Does.Contain("1 secret"));
            Assert.That(cut.Markup, Does.Contain("will expire in less than 60 days"));
        }
    }

    [Test]
    public void UsesCorrectPluralForm_WithMultipleSecrets()
    {
        // Arrange
        using var ctx = new TestContext();
        var config = Options.Create(new SecretExpirationConfig { MaxValidityYears = 3, DaysBeforeExpirationNotification = 60 });
        ctx.Services.AddSingleton(config);

        var secrets = new List<TestSecret>
        {
            new() { Expiration = DateTime.UtcNow.AddDays(10) },
            new() { Expiration = DateTime.UtcNow.AddDays(20) },
            new() { Expiration = DateTime.UtcNow.AddDays(30) }
        };

        // Act
        var cut = ctx.RenderComponent<BannerSecretExpiring>(parameters => parameters
            .Add(p => p.Secrets, secrets));

        // Assert
        Assert.That(cut.Markup, Does.Contain("3 secrets"));
    }

    [Test]
    public void HidesBanner_WhenDismissed()
    {
        // Arrange
        using var ctx = new TestContext();
        var config = Options.Create(new SecretExpirationConfig { MaxValidityYears = 3, DaysBeforeExpirationNotification = 60 });
        ctx.Services.AddSingleton(config);

        var secrets = new List<TestSecret>
        {
            new() { Expiration = DateTime.UtcNow.AddDays(30) }
        };

        var cut = ctx.RenderComponent<BannerSecretExpiring>(parameters => parameters
            .Add(p => p.Secrets, secrets));

        // Act
        var dismissButton = cut.Find("button.btn-close");
        dismissButton.Click();

        // Assert
        Assert.That(cut.Markup, Does.Not.Contain("Secrets Expiring Soon"));
    }

    [Test]
    public void DoesNotDisplayBanner_WhenNoSecretsExpiringSoon()
    {
        // Arrange
        using var ctx = new TestContext();
        var config = Options.Create(new SecretExpirationConfig { MaxValidityYears = 3, DaysBeforeExpirationNotification = 60 });
        ctx.Services.AddSingleton(config);

        var secrets = new List<TestSecret>
        {
            new() { Expiration = DateTime.UtcNow.AddDays(90) },
            new() { Expiration = DateTime.UtcNow.AddYears(1) },
            new() { Expiration = null }
        };

        // Act
        var cut = ctx.RenderComponent<BannerSecretExpiring>(parameters => parameters
            .Add(p => p.Secrets, secrets));

        // Assert
        Assert.That(cut.Markup, Does.Not.Contain("Secrets Expiring Soon"));
    }

    [Test]
    public void CalculatesExpiringSoon_BasedOnConfiguredThreshold()
    {
        // Arrange
        using var ctx = new TestContext();
        var config = Options.Create(new SecretExpirationConfig { MaxValidityYears = 3, DaysBeforeExpirationNotification = 30 });
        ctx.Services.AddSingleton(config);

        var secrets = new List<TestSecret>
        {
            new() { Expiration = DateTime.UtcNow.AddDays(20) }, // expiring soon (< 30 days)
            new() { Expiration = DateTime.UtcNow.AddDays(40) }  // not expiring soon (>= 30 days)
        };

        // Act
        var cut = ctx.RenderComponent<BannerSecretExpiring>(parameters => parameters
            .Add(p => p.Secrets, secrets));

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(cut.Markup, Does.Contain("1 secret"));
            Assert.That(cut.Markup, Does.Contain("will expire in less than 30 days"));
        }
    }

    [Test]
    public void ExcludesExpiredSecrets_FromExpiringCount()
    {
        // Arrange
        using var ctx = new TestContext();
        var config = Options.Create(new SecretExpirationConfig { MaxValidityYears = 3, DaysBeforeExpirationNotification = 60 });
        ctx.Services.AddSingleton(config);

        var secrets = new List<TestSecret>
        {
            new() { Expiration = DateTime.UtcNow.AddDays(-10) }, // expired - should NOT be counted
            new() { Expiration = DateTime.UtcNow.AddDays(30) }   // expiring soon
        };

        // Act
        var cut = ctx.RenderComponent<BannerSecretExpiring>(parameters => parameters
            .Add(p => p.Secrets, secrets));

        // Assert
        Assert.That(cut.Markup, Does.Contain("1 secret"));
    }
}
