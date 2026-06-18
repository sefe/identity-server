using Microsoft.Extensions.DependencyInjection;
using NSubstitute;
using System.Security.Claims;
using IdentityServer.Abstraction.Configs;
using IdentityServer.Abstraction.Contracts.MicrosoftGraph;
using IdentityServer.Data.Security;

namespace IdentityServer.AdminPortal.Test.Security;

/// <summary>
/// Cover constructor logic.
/// The rest is transitevely covered by other tests. 
/// </summary>
[TestFixture]
public  class UserGroupMembershipServiceTests
{
    [Test]
    public void Constructor_IfEmptyReaderGroupId_ThrowsException()
    {
        // Arrange
        var _authConfig = new AuthConfig() { ContributorGroupId = "group", ReaderGroupId = "" };
        var entraService = Substitute.For<IEntraUserService>();

        // Act & Assert
        var ex = Assert.Throws<InvalidOperationException>(() => new UserGroupMembershipService(entraService, _authConfig));
        Assert.That(ex.Message, Is.EqualTo("Readers Group not configured."));
    }

    [Test]
    public void Constructor_IfEmptyContributorGroupId_ThrowsException()
    {
        // Arrange
        var _authConfig = new AuthConfig() { ContributorGroupId = "", ReaderGroupId = "group" };
        var entraService = Substitute.For<IEntraUserService>();

        // Act & Assert
        var ex = Assert.Throws<InvalidOperationException>(() => new UserGroupMembershipService(entraService, _authConfig));
        Assert.That(ex.Message, Is.EqualTo("Contributors Group not configured."));
    }
}
