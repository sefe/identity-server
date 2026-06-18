using Microsoft.Extensions.DependencyInjection;
using NSubstitute;
using Telerik.DataSource;
using IdentityServer.Abstraction.Configs;
using IdentityServer.Abstraction.Contracts;
using IdentityServer.Abstraction.Contracts.MicrosoftGraph;
using IdentityServer.Abstraction.Entities.EntraEntities;
using IdentityServer.Abstraction.Entities.IdentityServerConfig.SystemPermissions;
using IdentityServer.AdminPortal.Server.Controllers;
using IdentityServer.AdminPortal.Test.Extensions;
using IdentityServer.Tests.Common;

namespace IdentityServer.AdminPortal.Test.Controller;

[TestFixture]
public class SystemPermissionRoleAssignmentControllerTests : ControllerTestBase
{
    private IAuthConfig _authConfig;
    private IEntraGroupService _entraGroupService;
    private SystemPermissionRoleAssignmentController _controller;
    private IStorage<SystemPermissionRole> _roleStorage;
    private readonly IEntraUserService _entraUserService = Substitute.For<IEntraUserService>();

    [SetUp]
    public void Setup()
    {
        _authConfig = new AuthConfig() { ContributorGroupId = "group-writer", ReaderGroupId = "group-reader" };

        _entraGroupService = Substitute.For<IEntraGroupService>();

        var provider = IoC.GetProvider(sc =>
        {
            sc.AddScoped(_ => _authConfig);
            sc.AddScoped(_ => _entraGroupService);
            sc.AddScoped(_ => _entraUserService);
            sc.AddScoped<SystemPermissionRoleAssignmentController>();
        });

        _controller = provider.GetRequiredService<SystemPermissionRoleAssignmentController>();
        _roleStorage = provider.GetRequiredService<IStorage<SystemPermissionRole>>();
    }

    [Test]
    public async Task GetEligibleUserAssignmentsPagedAsync_ReturnsEligibleUsers_ForReaderRole()
    {
        // Arrange
        var user = TestUser.SuperUser;
        var envId = 1;
        var roleType = SystemPermissionRoleType.Reader;
        var gridRequest = new DataSourceRequest { Page = 1, PageSize = 10 };

        await _roleStorage.AddAsync(new SystemPermissionRole { OId = "oid1", Name = "User1", SystemPermissionEnvironmentId = envId, RoleType = SystemPermissionRoleType.Reader });
        await _roleStorage.AddAsync(new SystemPermissionRole { OId = "oid2", Name = "User2", SystemPermissionEnvironmentId = envId, RoleType = SystemPermissionRoleType.Writer });

        var groupUsers = new[]
        {
            new User { OId = "oid1", DisplayName = "User1" },
            new User { OId = "oid3", DisplayName = "User3" }
        };
        _entraGroupService.GetGroupMembersAsync("group-reader").Returns(groupUsers.ToList());

        // Act
        var result = await _controller.Call_GetEligibleUserAssignmentsPagedAsync(gridRequest, envId, roleType, user);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result.CurrentPageData, Has.Count.EqualTo(1));
            Assert.That(result.CurrentPageData[0].OId, Is.EqualTo("oid3")); // existing readers or writers are not eligible for reader assignment
        }
    }

    [Test]
    public async Task GetEligibleUserAssignmentsPagedAsync_ReturnsEligibleUsers_ForWriterRole()
    {
        // Arrange
        var user = TestUser.SuperUser;
        var envId = 2;
        var roleType = SystemPermissionRoleType.Writer;
        var gridRequest = new DataSourceRequest { Page = 1, PageSize = 10 };
        await _roleStorage.AddAsync(new SystemPermissionRole { OId = "oid4", Name = "User4", SystemPermissionEnvironmentId = envId, RoleType = SystemPermissionRoleType.Writer });
        await _roleStorage.AddAsync(new SystemPermissionRole { OId = "oid5", Name = "User5", SystemPermissionEnvironmentId = envId, RoleType = SystemPermissionRoleType.Reader });

        var groupUsers = new[]
  {
            new User { OId = "oid3", DisplayName = "User3" },
            new User { OId = "oid4", DisplayName = "User4" },
            new User { OId = "oid5", DisplayName = "User5" }
        };
        _entraGroupService.GetGroupMembersAsync("group-writer").Returns(groupUsers.ToList());

        // Act
        var result = await _controller.Call_GetEligibleUserAssignmentsPagedAsync(gridRequest, envId, roleType, user);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result.CurrentPageData, Has.Count.EqualTo(2));
            Assert.That(result.CurrentPageData[0].OId, Is.EqualTo("oid3")); // user without assignments is eligible
            Assert.That(result.CurrentPageData[1].OId, Is.EqualTo("oid5")); // user with Reader assignment is eligible too
        }
    }

    [Test]
    public void GetEligibleUserAssignmentsPagedAsync_ThrowsArgumentException_ForUnsupportedRoleType()
    {
        // Arrange
        var user = TestUser.SuperUser;
        SetControllerContext(_controller, user);
        var envId = 3;
        var gridRequest = new DataSourceRequest { Page = 1, PageSize = 10 };
        // Act & Assert
        Assert.ThrowsAsync<ArgumentException>(() => _controller.GetEligibleUserAssignmentsPagedAsync(gridRequest, envId, (SystemPermissionRoleType)99));
    }
}
