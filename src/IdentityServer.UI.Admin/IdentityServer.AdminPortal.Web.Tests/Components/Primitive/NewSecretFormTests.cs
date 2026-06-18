using Bunit;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Options;
using IdentityServer.Abstraction.Configs;
using IdentityServer.AdminPortal.Web.Components.Primitive;
using TestContext = Bunit.TestContext;

namespace IdentityServer.AdminPortal.Web.Tests.Components.Primitive;

[TestFixture]
public class NewSecretFormTests
{
    [Test]
    public void RendersForm_WithValidityPeriodInput()
    {
        // Arrange
        using var ctx = new TestContext();
        var config = Options.Create(new SecretExpirationConfig { MaxValidityYears = 3, DaysBeforeExpirationNotification = 60 });
        ctx.Services.AddSingleton(config);

        // Act
        var cut = ctx.RenderComponent<NewSecretForm>(parameters => parameters
            .Add(p => p.ProhibitedValues, new List<string>()));

        // Assert
        var validityInput = cut.Find("#newSecretValidity");
        using (Assert.EnterMultipleScope())
        {
            Assert.That(validityInput, Is.Not.Null);
            Assert.That(cut.Markup, Does.Contain("Validity Period (years)"));
            Assert.That(cut.Markup, Does.Contain("Maximum: 3 years"));
        }
    }

    [Test]
    public void DisplaysMaxValidityHint_FromConfiguration()
    {
        // Arrange
        using var ctx = new TestContext();
        var config = Options.Create(new SecretExpirationConfig { MaxValidityYears = 10, DaysBeforeExpirationNotification = 60 });
        ctx.Services.AddSingleton(config);

        // Act
        var cut = ctx.RenderComponent<NewSecretForm>(parameters => parameters
            .Add(p => p.ProhibitedValues, new List<string>()));

        // Assert
        Assert.That(cut.Markup, Does.Contain("Maximum: 10 years"));
    }

    [Test]
    public void RendersCreateButton_WithPrimaryTheme()
    {
        // Arrange
        using var ctx = new TestContext();
        var config = Options.Create(new SecretExpirationConfig { MaxValidityYears = 3, DaysBeforeExpirationNotification = 60 });
        ctx.Services.AddSingleton(config);

        // Act
        var cut = ctx.RenderComponent<NewSecretForm>(parameters => parameters
            .Add(p => p.ProhibitedValues, new List<string>()));

        // Assert
        Assert.That(cut.Markup, Does.Contain("Create").And.Contain("k-button-solid-primary"));
    }

    [Test]
    public void RendersCancelButton_WithSecondaryTheme()
    {
        // Arrange
        using var ctx = new TestContext();
        var config = Options.Create(new SecretExpirationConfig { MaxValidityYears = 3, DaysBeforeExpirationNotification = 60 });
        ctx.Services.AddSingleton(config);

        // Act
        var cut = ctx.RenderComponent<NewSecretForm>(parameters => parameters
            .Add(p => p.ProhibitedValues, new List<string>()));

        // Assert
        Assert.That(cut.Markup, Does.Contain("Cancel").And.Contain("k-button-solid-secondary"));
    }

    [Test]
    public void RendersDescriptionField_WithRequiredLabel()
    {
        // Arrange
        using var ctx = new TestContext();
        var config = Options.Create(new SecretExpirationConfig { MaxValidityYears = 3, DaysBeforeExpirationNotification = 60 });
        ctx.Services.AddSingleton(config);

        // Act
        var cut = ctx.RenderComponent<NewSecretForm>(parameters => parameters
            .Add(p => p.ProhibitedValues, new List<string>()));

        // Assert
        var descriptionInput = cut.Find("#newSecretDescription");
        using (Assert.EnterMultipleScope())
        {
            Assert.That(descriptionInput, Is.Not.Null);
            Assert.That(cut.Markup, Does.Contain("Description"));
        }
    }
}
