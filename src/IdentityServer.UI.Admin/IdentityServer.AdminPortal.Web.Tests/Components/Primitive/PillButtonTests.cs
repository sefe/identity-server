using Bunit;
using IdentityServer.AdminPortal.Web.Components.Primitive;
using Microsoft.AspNetCore.Components;

namespace IdentityServer.AdminPortal.Web.Tests.Components.Primitive;

[TestFixture]
public class PillButtonTests : Bunit.TestContext
{
    [Test]
    public void RendersDisabledButtonWithPlusButton_WhenIsAddTrue()
    {
        // Arrange
        var text = "Test Pill";

        // Act
        var cut = RenderComponent<PillButton>(parameters => parameters
            .Add(p => p.Text, text)
            .Add(p => p.IsAdd, true)
        );

        // Assert
        var div = cut.Find("div.btn-group");
        div.MarkupMatches("<div diff:ignoreAttributes><button type=\"button\" class=\"btn btn-light border-dark\" disabled>Test Pill</button><button diff:ignoreAttributes>+</button></div>");
    }

    [Test]
    public void RendersDisabledButtonWithTrashButton_WhenIsAddFalse()
    {
        // Arrange & Act
        var text = "Test Pill";
        var cut = RenderComponent<PillButton>(parameters => parameters
                    .Add(p => p.Text, text)
                    .Add(p => p.IsAdd, false));

        // Assert
        var div = cut.Find("div.btn-group");
        div.MarkupMatches("<div diff:ignoreAttributes><button type=\"button\" class=\"btn btn-light border-dark\" disabled>Test Pill</button><button diff:ignoreAttributes><span diff:ignoreChildren class=\"telerik-blazor k-icon k-svg-icon k-svg-i-trash\" aria-hidden=\"true\"></span></button></div>");
    }

    [TestCase(true)]
    [TestCase(false)]
    public void InvokesCallback_WhenNotReadonlyOnButtonClick(bool isAdd)
    {
        // Arrange
        var clicked = false;
        var cut = RenderComponent<PillButton>(parameters => parameters
            .Add(p => p.Text, "Add")
            .Add(p => p.IsAdd, isAdd)
            .Add(p => p.OnClick, EventCallback.Factory.Create(this, () => clicked = true))
        );

        // Act
        cut.FindAll("button")[1].Click();

        // Assert
        Assert.That(clicked, Is.True);
    }

    [Test]
    public void RendersOnlyText_WhenReadonly()
    {
        // Act
        var cut = RenderComponent<PillButton>(parameters => parameters
            .Add(p => p.Text, "Add")
            .Add(p => p.IsReadonly, true)
        );

        // Assert
        var div = cut.Find("div.btn-group");
        div.MarkupMatches("<div diff:ignoreAttributes><button type=\"button\" class=\"btn btn-light border-dark\" disabled>Add</button></div>");
    }
}
