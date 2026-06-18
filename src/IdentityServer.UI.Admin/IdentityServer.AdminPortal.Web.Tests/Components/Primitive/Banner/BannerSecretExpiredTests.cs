using Bunit;
using IdentityServer.AdminPortal.Web.Components.Primitive.Banner;
using TestContext = Bunit.TestContext;

namespace IdentityServer.AdminPortal.Web.Tests.Components.Primitive.Banner;

[TestFixture]
public class BannerSecretExpiredTests
{
    [Test]
    public void CalculatesFilteredSecretsCount_WithExpired()
    {
        // Arrange
        using var ctx = new TestContext();

        var secrets = new List<TestSecret>
        {
            new() { Expiration = DateTime.UtcNow.AddDays(-10) }, // expired
            new() { Expiration = DateTime.UtcNow.AddDays(-5) },  // expired
            new() { Expiration = DateTime.UtcNow.AddDays(30) },  // not expired
            new() { Expiration = null }                          // no expiration
        };

        // Act
        var cut = ctx.RenderComponent<BannerSecretExpired>(parameters => parameters
            .Add(p => p.Secrets, secrets));

        // Assert
        Assert.That(cut.Markup, Does.Contain("2 secrets"));
    }

    [Test]
    public void DisplaysBanner_WhenSecretsExpired()
    {
        // Arrange
        using var ctx = new TestContext();

        var secrets = new List<TestSecret>
        {
            new() { Expiration = DateTime.UtcNow.AddDays(-10) }
        };

        // Act
        var cut = ctx.RenderComponent<BannerSecretExpired>(parameters => parameters
            .Add(p => p.Secrets, secrets));

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(cut.Markup, Does.Contain("Secrets Expired"));
            Assert.That(cut.Markup, Does.Contain("1 secret"));
            Assert.That(cut.Markup, Does.Contain("has expired"));
        }
    }

    [Test]
    public void UsesCorrectPluralForm_WithMultipleSecrets()
    {
        // Arrange
        using var ctx = new TestContext();

        var secrets = new List<TestSecret>
        {
            new() { Expiration = DateTime.UtcNow.AddDays(-30) },
            new() { Expiration = DateTime.UtcNow.AddDays(-20) },
            new() { Expiration = DateTime.UtcNow.AddDays(-10) }
        };

        // Act
        var cut = ctx.RenderComponent<BannerSecretExpired>(parameters => parameters
            .Add(p => p.Secrets, secrets));

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(cut.Markup, Does.Contain("3 secrets"));
            Assert.That(cut.Markup, Does.Contain("have expired"));
        }
    }

    [Test]
    public void HidesBanner_WhenDismissed()
    {
        // Arrange
        using var ctx = new TestContext();

        var secrets = new List<TestSecret>
        {
            new() { Expiration = DateTime.UtcNow.AddDays(-10) }
        };

        var cut = ctx.RenderComponent<BannerSecretExpired>(parameters => parameters
            .Add(p => p.Secrets, secrets));

        // Act
        var dismissButton = cut.Find("button.btn-close");
        dismissButton.Click();

        // Assert
        Assert.That(cut.Markup, Does.Not.Contain("Secrets Expired"));
    }

    [Test]
    public void DoesNotDisplayBanner_WhenNoSecretsExpired()
    {
        // Arrange
        using var ctx = new TestContext();

        var secrets = new List<TestSecret>
        {
            new() { Expiration = DateTime.UtcNow.AddDays(30) },
            new() { Expiration = DateTime.UtcNow.AddYears(1) },
            new() { Expiration = null }
        };

        // Act
        var cut = ctx.RenderComponent<BannerSecretExpired>(parameters => parameters
            .Add(p => p.Secrets, secrets));

        // Assert
        Assert.That(cut.Markup, Does.Not.Contain("Secrets Expired"));
    }

    [Test]
    public void ExcludesNonExpiredSecrets_FromExpiredCount()
    {
        // Arrange
        using var ctx = new TestContext();

        var secrets = new List<TestSecret>
        {
            new() { Expiration = DateTime.UtcNow.AddDays(-10) }, // expired
            new() { Expiration = DateTime.UtcNow.AddDays(30) }   // not expired - should NOT be counted
        };

        // Act
        var cut = ctx.RenderComponent<BannerSecretExpired>(parameters => parameters
            .Add(p => p.Secrets, secrets));

        // Assert
        Assert.That(cut.Markup, Does.Contain("1 secret"));
    }

    [Test]
    public void UsesAlertDangerCssClass()
    {
        // Arrange
        using var ctx = new TestContext();

        var secrets = new List<TestSecret>
        {
            new() { Expiration = DateTime.UtcNow.AddDays(-10) }
        };

        // Act
        var cut = ctx.RenderComponent<BannerSecretExpired>(parameters => parameters
            .Add(p => p.Secrets, secrets));

        // Assert
        Assert.That(cut.Markup, Does.Contain("alert-danger"));
    }

    [Test]
    public void CountsSecretExpiredToday_AsExpired()
    {
        // Arrange
        using var ctx = new TestContext();

        var secrets = new List<TestSecret>
        {
            new() { Expiration = DateTime.UtcNow.AddHours(-1) } // expired today
        };

        // Act
        var cut = ctx.RenderComponent<BannerSecretExpired>(parameters => parameters
            .Add(p => p.Secrets, secrets));

        // Assert
        Assert.That(cut.Markup, Does.Contain("1 secret"));
    }
}
