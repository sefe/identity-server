using Bunit;
using IdentityServer.Abstraction.Entities.IdentityServerConfig.SystemPermissions;
using IdentityServer.AdminPortal.Web.Components.Primitive;

namespace IdentityServer.AdminPortal.Web.Tests.Components.Primitive;

[TestFixture]
public class AccessLevelLinkTests : Bunit.TestContext
{
    [Test]
    public void RendersSpan_WhenAccessLevelIsNone()
    {
        // Arrange
        var text = "Some Text";

        // Act
        var cut = RenderComponent<AccessLevelLink>(parameters => parameters
            .Add(p => p.AccessLevel, SystemPermissionRoleType.None)
            .Add(p => p.Text, text)
            .Add(p => p.Href, "https://example.com")
        );

        // Assert
        Assert.That(cut.Markup, Is.EqualTo($"<span class=\"text-break\">{text}</span>"));
    }

    [TestCase(SystemPermissionRoleType.Reader, "Reader Text", "/reader")]
    [TestCase(SystemPermissionRoleType.Writer, "Writer Text", "/writer")]
    public void RendersLink_WhenAccessLevelIsNotNone(SystemPermissionRoleType accessLevel, string text, string href)
    {
        // Act
        var cut = RenderComponent<AccessLevelLink>(parameters => parameters
            .Add(p => p.AccessLevel, accessLevel)
            .Add(p => p.Text, text)
            .Add(p => p.Href, href)
        );

        // Assert
        cut.Find("a").MarkupMatches($"<a class=\"btn btn-link text-start text-break text-decoration-underline\" href=\"{href}\">{text}</a>");
    }

    [Test]
    public void RendersEmptyText_WhenTextIsNotProvided()
    {
        // Act
        var cut = RenderComponent<AccessLevelLink>(parameters => parameters
            .Add(p => p.AccessLevel, SystemPermissionRoleType.None)
        );

        // Assert
        Assert.That(cut.Markup, Is.EqualTo("<span class=\"text-break\"></span>"));
    }
}
