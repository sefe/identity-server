// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

using System.Security.Claims;
using Microsoft.Extensions.DependencyInjection;
using IdentityServer.Abstraction.DTO.SystemPermissions;
using IdentityServer.Abstraction.Entities.IdentityServerConfig.SystemPermissions;
using IdentityServer.Abstraction.Exceptions;
using IdentityServer.AdminPortal.Server.Controllers;
using IdentityServer.AdminPortal.Test.Extensions;

namespace IdentityServer.AdminPortal.Test.Security;

[TestFixture]
public class StandardPermissionSecurityTests : PermissionSecurityTestBase
{
    protected SystemPermissionController _controller;

    [SetUp]
    public void Setup()
    {
        var provider = base.Setup(sc =>
        {
            sc.AddScoped<SystemPermissionController>();
        });

        _controller = provider.GetRequiredService<SystemPermissionController>();
    }

    public static IEnumerable<TestCaseData> RoleCanReadUnassignedPermission
    {
        get
        {
            yield return new TestCaseData(Reader, false).SetArgDisplayNames(nameof(Reader));
            yield return new TestCaseData(Contributor, false).SetArgDisplayNames(nameof(Contributor));
            yield return new TestCaseData(Admin, true).SetArgDisplayNames(nameof(Admin));
        }
    }

    [Test]
    [TestCaseSource(nameof(RoleCanReadUnassignedPermission))]
    public async Task GetPermission_IfUnassigned_DependsOnPermissions(ClaimsPrincipal user, bool expectSuccess)
    {
        // Arrange
        await CreateDefaultPermissionInfrastructure();

        // do not assign any permissions

        if (expectSuccess)
        {
            var result1 = await _controller.Call_GetSystemPermissionByIdAsync(_permission1.Id, user);
            Assert.That(result1, Is.Not.Null);
            Assert.That(result1.Id, Is.EqualTo(_permission1.Id));
        }
        else
        {
            Assert.ThrowsAsync<EntityAccessException>(() => _controller.Call_GetSystemPermissionByIdAsync(_permission1.Id, user));
        }
    }

    public static IEnumerable<TestCaseData> RoleCanUpdateUnassignedPermission
    {
        get
        {
            yield return new TestCaseData(Reader, false).SetArgDisplayNames(nameof(Reader));
            yield return new TestCaseData(Contributor, false).SetArgDisplayNames(nameof(Contributor));
            yield return new TestCaseData(Admin, true).SetArgDisplayNames(nameof(Admin));
        }
    }

    [Test]
    [TestCaseSource(nameof(RoleCanUpdateUnassignedPermission))]
    public async Task UpdatePermission_IfUnassigned_DependsOnPermissions(ClaimsPrincipal user, bool expectSuccess)
    {
        // Arrange
        await CreateDefaultPermissionInfrastructure();

        // do not assign any permissions

        var updatedDescription = $"Updated description {Guid.NewGuid()}";

        // Act
        var updateItem = new SystemPermissionDtoUpdate { Id = _permission1.Id, Description = updatedDescription };

        if (expectSuccess)
        {
            var result1 = await _controller.Call_UpdateSystemPermissionAsync(updateItem, user);
            // Assert
            using (Assert.EnterMultipleScope())
            {
                Assert.That(result1.Id, Is.EqualTo(_permission1.Id));
                Assert.That(result1.Description, Is.EqualTo(updatedDescription));
            }
        }
        else
        {
            Assert.ThrowsAsync<EntityAccessException>(() => _controller.Call_UpdateSystemPermissionAsync(updateItem, user));
        }
    }

    public static IEnumerable<TestCaseData> RoleCanDeleteUnassignedPermission
    {
        get
        {
            yield return new TestCaseData(Reader, false).SetArgDisplayNames(nameof(Reader));
            yield return new TestCaseData(Contributor, false).SetArgDisplayNames(nameof(Contributor));
            yield return new TestCaseData(Admin, true).SetArgDisplayNames(nameof(Admin));
        }
    }

    [Test]
    [TestCaseSource(nameof(RoleCanDeleteUnassignedPermission))]
    public async Task DeletePermission_IfUnassigned_DependsOnPermissions(ClaimsPrincipal user, bool expectSuccess)
    {
        // Arrange
        await CreateDefaultPermissionInfrastructure();

        // do not assign any permissions

        // Act
        if (expectSuccess)
        {
            var result1 = await _controller.Call_DeleteSystemPermissionByIdAsync(_permission1.Id, user);
            // Assert
            Assert.That(result1.Value, Is.EqualTo(_permission1.Id));
        }
        else
        {
            Assert.ThrowsAsync<EntityAccessException>(() => _controller.Call_DeleteSystemPermissionByIdAsync(_permission1.Id, user));
        }
    }

    public static IEnumerable<TestCaseData> RoleCanDeletePermissionIfAssigned
    {
        get
        {
            yield return new TestCaseData(Reader, "Reader", false).SetArgDisplayNames(nameof(Reader), "Reader");
            yield return new TestCaseData(Reader, "PartialWriter", false).SetArgDisplayNames(nameof(Reader), "PartialWriter");
            yield return new TestCaseData(Reader, "FullWriter", false).SetArgDisplayNames(nameof(Reader), "FullWriter");
            yield return new TestCaseData(Contributor, "Reader", false).SetArgDisplayNames(nameof(Contributor), "Reader");
            yield return new TestCaseData(Contributor, "PartialWriter", false).SetArgDisplayNames(nameof(Contributor), "PartialWriter");
            yield return new TestCaseData(Contributor, "FullWriter", true).SetArgDisplayNames(nameof(Contributor), "FullWriter");
        }
    }

    [Test]
    [TestCaseSource(nameof(RoleCanDeletePermissionIfAssigned))]
    public async Task DeletePermission_IfAssigned_DependsOnPermissions(ClaimsPrincipal user, string assignments, bool expectSuccess)
    {
        // Arrange
        await CreateDefaultPermissionInfrastructure_With1Permission_And2Environments();

        switch (assignments)
        {
            case "Reader":
                _permission1 = await AssignPermissionToUser(user, _permission1, _permission1.Environments[0].Environment, SystemPermissionRoleType.Reader);
                break;
            case "PartialWriter":
                _permission1 = await AssignPermissionToUser(user, _permission1, _permission1.Environments[0].Environment, SystemPermissionRoleType.Writer);
                _permission1 = await AssignPermissionToUser(user, _permission1, _permission1.Environments[1].Environment, SystemPermissionRoleType.Reader);
                break;
            case "FullWriter":
                _permission1 = await AssignPermissionToUser(user, _permission1, _permission1.Environments[0].Environment, SystemPermissionRoleType.Writer);
                _permission1 = await AssignPermissionToUser(user, _permission1, _permission1.Environments[1].Environment, SystemPermissionRoleType.Writer);
                break;
        }

        // Act
        if (expectSuccess)
        {
            var result1 = await _controller.Call_DeleteSystemPermissionByIdAsync(_permission1.Id, user);
            // Assert
            Assert.That(result1.Value, Is.EqualTo(_permission1.Id));
        }
        else
        {
            Assert.ThrowsAsync<EntityAccessException>(() => _controller.Call_DeleteSystemPermissionByIdAsync(_permission1.Id, user));
        }
    }

    public static IEnumerable<TestCaseData> RoleCanUpdatePermissionIfAssigned
    {
        get
        {
            yield return new TestCaseData(Reader, "Reader", false).SetArgDisplayNames(nameof(Reader), "Reader");
            yield return new TestCaseData(Reader, "PartialWriter", false).SetArgDisplayNames(nameof(Reader), "PartialWriter");
            yield return new TestCaseData(Reader, "FullWriter", false).SetArgDisplayNames(nameof(Reader), "FullWriter");
            yield return new TestCaseData(Contributor, "Reader", false).SetArgDisplayNames(nameof(Contributor), "Reader");
            yield return new TestCaseData(Contributor, "PartialWriter", false).SetArgDisplayNames(nameof(Contributor), "PartialWriter");
            yield return new TestCaseData(Contributor, "FullWriter", true).SetArgDisplayNames(nameof(Contributor), "FullWriter");
        }
    }

    [Test]
    [TestCaseSource(nameof(RoleCanUpdatePermissionIfAssigned))]
    public async Task UpdatePermission_IfAssigned_DependsOnPermissions(ClaimsPrincipal user, string assignments, bool expectSuccess)
    {
        // Arrange
        await CreateDefaultPermissionInfrastructure_With1Permission_And2Environments();

        switch (assignments)
        {
            case "Reader":
                _permission1 = await AssignPermissionToUser(user, _permission1, _permission1.Environments[0].Environment, SystemPermissionRoleType.Reader);
                break;
            case "PartialWriter":
                _permission1 = await AssignPermissionToUser(user, _permission1, _permission1.Environments[0].Environment, SystemPermissionRoleType.Writer);
                _permission1 = await AssignPermissionToUser(user, _permission1, _permission1.Environments[1].Environment, SystemPermissionRoleType.Reader);
                break;
            case "FullWriter":
                _permission1 = await AssignPermissionToUser(user, _permission1, _permission1.Environments[0].Environment, SystemPermissionRoleType.Writer);
                _permission1 = await AssignPermissionToUser(user, _permission1, _permission1.Environments[1].Environment, SystemPermissionRoleType.Writer);
                break;
        }

        var updatedDescription = $"Updated description {Guid.NewGuid()}";

        // Act
        var updateItem = new SystemPermissionDtoUpdate { Id = _permission1.Id, Description = updatedDescription };

        if (expectSuccess)
        {
            var result1 = await _controller.Call_UpdateSystemPermissionAsync(updateItem, user);
            // Assert
            using (Assert.EnterMultipleScope())
            {
                Assert.That(result1.Id, Is.EqualTo(_permission1.Id));
                Assert.That(result1.Description, Is.EqualTo(updatedDescription));
            }
        }
        else
        {
            Assert.ThrowsAsync<EntityAccessException>(() => _controller.Call_UpdateSystemPermissionAsync(updateItem, user));
        }
    }

    [Test]
    public async Task GetPermission_ByReader_CanReadIfAssigned()
    {
        // Arrange
        await CreateDefaultPermissionInfrastructure();

        _permission1 = await AssignPermissionToUser(Reader, _permission1, _permission1.Environments[0].Environment, SystemPermissionRoleType.Reader);

        // Act
        var result1 = await _controller.Call_GetSystemPermissionByIdAsync(_permission1.Id, Reader);

        // Assert
        Assert.That(result1, Is.Not.Null);
        Assert.ThrowsAsync<EntityAccessException>(() => _controller.Call_GetSystemPermissionByIdAsync(_permission2.Id, Reader));
    }

    [Test]
    public async Task GetPermission_ByReader_CanSeeAllEnvironmentsIfAssignedToOneEnvironment()
    {
        // Arrange
        var user = Reader;

        await CreateDefaultPermissionInfrastructure_With1Permission_And2Environments();

        _permission1 = await AssignPermissionToUser(user, _permission1, _permission1.Environments[0].Environment, SystemPermissionRoleType.Reader);

        // Act
        var result = await _controller.Call_GetSystemPermissionByIdAsync(_permission1.Id, user);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result.Id, Is.EqualTo(_permission1.Id));
            Assert.That(result.Environments, Has.Count.EqualTo(2));
            foreach (var item in result.Environments)
            {
                var expected = _permission1.Environments.First(e => e.Environment == item.Environment);
                using (Assert.EnterMultipleScope())
                {
                    Assert.That(item.Id, Is.EqualTo(expected.Id));
                    Assert.That(item.Environment, Is.EqualTo(expected.Environment));
                    Assert.That(item.SystemPermissionId, Is.EqualTo(expected.SystemPermissionId));

                    foreach (var itemP in item.Permissions)
                    {
                        var expectedP = expected.Permissions.First(e => e.OId == itemP.OId);
                        using (Assert.EnterMultipleScope())
                        {
                            Assert.That(itemP.Id, Is.EqualTo(expectedP.Id));
                            Assert.That(itemP.Name, Is.EqualTo(expectedP.Name));
                            Assert.That(itemP.RoleType, Is.EqualTo(expectedP.RoleType));
                            Assert.That(itemP.SystemPermissionEnvironmentId, Is.EqualTo(expectedP.SystemPermissionEnvironmentId));
                        }
                    }
                }
            }
        }
    }

    [Test]
    [TestCase(SystemPermissionRoleType.Reader)]
    [TestCase(SystemPermissionRoleType.Writer)]
    public async Task GetPermission_ByContributor_CanReadAssigned_Setup1(SystemPermissionRoleType permissionType)
    {
        // Arrange
        var user = Contributor;

        await CreateDefaultPermissionInfrastructure();

        _permission1 = await AssignPermissionToUser(user, _permission1, _permission1.Environments[0].Environment, permissionType);

        // Act
        var result1 = await _controller.Call_GetSystemPermissionsPagedAsync(user);

        // Assert can see the system in the list of all systems
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result1, Has.Count.EqualTo(2));
            Assert.That(result1.Any(_ => _.Id == _permission1.Id && _.AccessLevel == permissionType), Is.True);
            Assert.That(result1.Any(_ => _.Id == _permission2.Id && _.AccessLevel == SystemPermissionRoleType.None), Is.True);
        }

        var result2 = await _controller.Call_GetSystemPermissionByIdAsync(_permission1.Id, user);

        // Assert can see the system details
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result2.Id, Is.EqualTo(_permission1.Id));
            Assert.That(result2.Environments, Has.Count.EqualTo(_permission1.Environments.Count));
        }
    }

    [Test]
    [TestCase(SystemPermissionRoleType.Reader)]
    [TestCase(SystemPermissionRoleType.Writer)]
    public async Task GetPermission_ByContributor_CanReadAssigned_Setup2(SystemPermissionRoleType permissionType)
    {
        // Arrange
        var user = Contributor;

        await CreateDefaultPermissionInfrastructure_With1Permission_And2Environments();

        _permission1 = await AssignPermissionToUser(user, _permission1, _permission1.Environments[0].Environment, permissionType);

        // Act
        var result1 = await _controller.Call_GetSystemPermissionsPagedAsync(user);

        // Assert can see the system in the list of all systems
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result1, Has.Count.EqualTo(1));
            Assert.That(result1[0].Id, Is.EqualTo(_permission1.Id));
        }

        var result2 = await _controller.Call_GetSystemPermissionByIdAsync(_permission1.Id, user);

        // Assert can see the system details
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result2.Id, Is.EqualTo(_permission1.Id));
            Assert.That(result2.Environments, Has.Count.EqualTo(_permission1.Environments.Count));
        }
    }
}
