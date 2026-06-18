using IdentityServer.AdminPortal.Web.Components.Primitive;

namespace IdentityServer.AdminPortal.Web.Tests.Components.Primitive;

[TestFixture]
public class CardHeaderTextTests : Bunit.TestContext
{
    [Test]
    public void RendersHeaderText_WhenTextIsProvided()
    {
        // Arrange
        var text = "Header Title";

        // Act
        var cut = RenderComponent<CardHeaderText>(parameters => parameters
            .Add(p => p.Text, text)
        );

        // Assert
        Assert.That(cut.Markup, Is.EqualTo($"<div class=\"row\"><h5 class=\"my-auto\">{text}</h5></div>"));
    }

    [Test]
    public void RendersEmptyHeader_WhenTextIsNull()
    {
        // Act
        var cut = RenderComponent<CardHeaderText>(parameters => parameters
            .Add(p => p.Text, null)
        );

        // Assert
        Assert.That(cut.Markup, Is.EqualTo("<div class=\"row\"><h5 class=\"my-auto\"></h5></div>"));
    }
}
