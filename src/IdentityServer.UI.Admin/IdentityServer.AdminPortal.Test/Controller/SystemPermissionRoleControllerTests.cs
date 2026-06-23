// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

using Microsoft.AspNetCore.Mvc;
using Microsoft.Extensions.DependencyInjection;
using NSubstitute;
using IdentityServer.Abstraction.DTO.SystemPermissions;
using IdentityServer.Abstraction.Entities.EntraEntities;
using IdentityServer.Abstraction.Entities.IdentityServerConfig.SystemPermissions;
using IdentityServer.Abstraction.Exceptions;
using IdentityServer.Abstraction.Extensions;
using IdentityServer.AdminPortal.Server.Controllers;
using IdentityServer.AdminPortal.Test.Extensions;
using IdentityServer.Tests.Common;

namespace IdentityServer.AdminPortal.Test.Controller;

public class SystemPermissionRoleControllerTests : ControllerTestBase
{
    private readonly SystemPermissionUtility _permissionUtil = new();
    private SystemPermissionRoleController _roleController;

    [SetUp]
    public void Setup()
    {
        var provider = IoC.GetProvider(sc =>
        {
            _permissionUtil.AddToServiceCollection(sc);
            sc.AddScoped<SystemPermissionRoleController>();
        });

        _permissionUtil.Setup(provider);

        _roleController = provider.GetRequiredService<SystemPermissionRoleController>();
    }

    [Test]
    [TestCaseSource(typeof(SystemPermissionRelationshipTestCases), nameof(SystemPermissionRelationshipTestCases.SystemPermissionCreateUnboundData))]
    public async Task CreateRole_WithWrongParent_Fails(string userName, SystemPermissionRoleType assignment)
    {
        // Arrange
        // permission 1 -> env1 -> client 1
        var user = TestUser.Get(userName);
        var oid = user.GetUserObjectId();
        var nonExistingEnvironmentId = Random.Shared.Next(1000, int.MaxValue);

        var sp = await _permissionUtil.CreatePermission(TestUser.SuperUser, SystemPermissionUtility.GetNewSystemPermission(), _permissionUtil.DefaultEnvironments);
        if (assignment != SystemPermissionRoleType.None)
        {
            await _permissionUtil.AssignPermissionToUser(user, sp, sp.Environments[0].Environment, assignment);
        }

        _permissionUtil.EntraUserServiceMock.GetUserByObjectIdAsync(oid).Returns(Task.FromResult(
            new UserResponse
            {
                Users = new List<User> { new() { DisplayName = "test user", OId = oid } }
            }));

        var role = new SystemPermissionRoleDtoCreate
        {
            OId = oid,
            RoleType = SystemPermissionRoleType.Reader,
            SystemPermissionEnvironmentId = nonExistingEnvironmentId,
        };

        // Act & Assert
        Assert.ThrowsAsync<EntityReferenceException>(() => _roleController.Call_CreateSystemPermissionRoleAsync(role, user));
    }

    [Test]
    public async Task CreateRole_WithDuplicateAssignment_Fails()
    {
        // Arrange
        // user gets Writer permission by default. Trying to add again must fail.
        var sp = await _permissionUtil.CreatePermission(TestUser.SuperUser, SystemPermissionUtility.GetNewSystemPermission(), _permissionUtil.DefaultEnvironments);
        var env = sp.Environments[0];

        var role = new SystemPermissionRoleDtoCreate
        {
            OId = TestUser.SuperUser.GetUserObjectId(),
            RoleType = SystemPermissionRoleType.Writer,
            SystemPermissionEnvironmentId = env.Id,
        };

        // Act & Assert
        Assert.ThrowsAsync<EntityAlreadyExistsException>(() => _roleController.Call_CreateSystemPermissionRoleAsync(role, TestUser.SuperUser));
    }

    [Test]
    public async Task CreateRole_Writer_WithInsufficientPermissions_Fails()
    {
        // Arrange
        var oid = TestUser.Reader.GetUserObjectId();
        var sp = await _permissionUtil.CreatePermission(TestUser.SuperUser, SystemPermissionUtility.GetNewSystemPermission(), _permissionUtil.DefaultEnvironments);

        _permissionUtil.EntraUserServiceMock.GetUserByObjectIdAsync(oid).Returns(Task.FromResult(
            new UserResponse
            {
                Users = new List<User> { new() { DisplayName = "test user", OId = oid } }
            }));

        var role = new SystemPermissionRoleDtoCreate
        {
            OId = oid,
            RoleType = SystemPermissionRoleType.Writer,
            SystemPermissionEnvironmentId = sp.Environments[0].Id,
        };

        // Act & Assert
        Assert.ThrowsAsync<UserInsufficientRoleException>(() => _roleController.Call_CreateSystemPermissionRoleAsync(role, TestUser.SuperUser));
    }

    [Test]
    public async Task CreateRole_Reader_WithInsufficientPermissions_Fails()
    {
        // Arrange
        var name = "test user";
        var oid = Guid.NewGuid().ToString();
        var testUser = TestUser.CreateClaimsPrincipal(name, oid); // no roles assigned
        var sp = await _permissionUtil.CreatePermission(TestUser.SuperUser, SystemPermissionUtility.GetNewSystemPermission(), _permissionUtil.DefaultEnvironments);

        _permissionUtil.EntraUserServiceMock.GetUserByObjectIdAsync(oid).Returns(Task.FromResult(
            new UserResponse
            {
                Users = new List<User> { new() { DisplayName = name, OId = oid } }
            }));

        var role = new SystemPermissionRoleDtoCreate
        {
            OId = oid,
            RoleType = SystemPermissionRoleType.Reader,
            SystemPermissionEnvironmentId = sp.Environments[0].Id,
        };

        // Act & Assert
        Assert.ThrowsAsync<UserInsufficientRoleException>(() => _roleController.Call_CreateSystemPermissionRoleAsync(role, TestUser.SuperUser));
    }

    [Test]
    public async Task CreateRole_WithUnsupportedRole_Fails()
    {
        // Arrange
        var oid = TestUser.Contributor.GetUserObjectId();
        var sp = await _permissionUtil.CreatePermission(TestUser.SuperUser, SystemPermissionUtility.GetNewSystemPermission(), _permissionUtil.DefaultEnvironments);

        _permissionUtil.EntraUserServiceMock.GetUserByObjectIdAsync(oid).Returns(Task.FromResult(
            new UserResponse
            {
                Users = new List<User> { new() { DisplayName = "test user", OId = oid } }
            }));

        var role = new SystemPermissionRoleDtoCreate
        {
            OId = oid,
            RoleType = SystemPermissionRoleType.None,
            SystemPermissionEnvironmentId = sp.Environments[0].Id,
        };

        // Act & Assert
        Assert.ThrowsAsync<InvalidOperationException>(() => _roleController.Call_CreateSystemPermissionRoleAsync(role, TestUser.SuperUser));
    }

    [Test]
    [TestCaseSource(typeof(SystemPermissionRelationshipTestCases), nameof(SystemPermissionRelationshipTestCases.SystemPermissionCreateUserRoleData))]
    public async Task CreateRole_WithWrongUserId_Fails(string userName, SystemPermissionRoleType assignment)
    {
        // Arrange
        // permission 1 -> env1 -> client 1
        var user = TestUser.Get(userName);

        // duplicated permissions are not allowed, user cannot add self
        var userToAdd_oid = Guid.NewGuid().ToString();

        var sp = await _permissionUtil.CreatePermission(TestUser.SuperUser, SystemPermissionUtility.GetNewSystemPermission(), _permissionUtil.DefaultEnvironments);
        if (assignment != SystemPermissionRoleType.None)
        {
            sp = await _permissionUtil.AssignPermissionToUser(user, sp, sp.Environments[0].Environment, assignment);
        }

        _permissionUtil.EntraUserServiceMock.GetUserByObjectIdAsync(userToAdd_oid).Returns(Task.FromResult(
            new UserResponse
            {
                Users = new List<User>() // emulate not found
            }));

        var role = new SystemPermissionRoleDtoCreate
        {
            OId = userToAdd_oid,
            RoleType = SystemPermissionRoleType.Reader,
            SystemPermissionEnvironmentId = sp.Environments[0].Id,
        };

        // Act & Assert
        Assert.ThrowsAsync<EntityReferenceException>(() => _roleController.Call_CreateSystemPermissionRoleAsync(role, user));
    }

    [Test]
    public async Task DeleteSystemPermissionRoleByIdAsync_WhenSingleWriter_Fails()
    {
        // Arrange
        // permission 1 -> env1: writer Contributor
        var sp = await _permissionUtil.CreatePermission(TestUser.Contributor, SystemPermissionUtility.GetNewSystemPermission(), _permissionUtil.DefaultEnvironments);
        var role = sp.Environments[0].Permissions[0];

        // Act & Assert
        Assert.ThrowsAsync<EntityReferenceException>(() => _roleController.Call_DeleteSystemPermissionRoleByIdAsync(role.Id, TestUser.Admin));
    }

    [Test]
    public async Task DeleteSystemPermissionRoleByIdAsync_WhenMultipleWriters_Succeeds()
    {
        // Arrange
        // permission1 -> env1: writers Admin, Contributor
        var sp = await _permissionUtil.CreatePermission(TestUser.SuperUser, SystemPermissionUtility.GetNewSystemPermission(), _permissionUtil.DefaultEnvironments);
        var env = sp.Environments[0];

        sp = await _permissionUtil.AssignPermissionToUser(TestUser.Contributor, sp, env.Environment, SystemPermissionRoleType.Writer);
        var oid = TestUser.Contributor.GetUserObjectId();
        var role1 = sp.Environments[0].Permissions.First(r => r.OId == oid);

        // Act
        var result = await _roleController.Call_DeleteSystemPermissionRoleByIdAsync(role1.Id, TestUser.Admin);

        // Assert
        Assert.That(result, Is.EqualTo(role1.Id));
    }

    [Test]
    public async Task DeleteSystemPermissionRoleByIdAsync_WhenLastFullWriter_Fails()
    {
        // Arrange
        // permission1 -> env1: writers SuperUser, Contributor
        // permission1 -> env2: writer SuperUser (Contributor is not a writer on env2, so only SuperUser is a full writer)
        var sp = await _permissionUtil.CreatePermission(TestUser.SuperUser, SystemPermissionUtility.GetNewSystemPermission(), _permissionUtil.StandardEnvironments);

        sp = await _permissionUtil.AssignPermissionToUser(TestUser.Contributor, sp, sp.Environments[0].Environment, SystemPermissionRoleType.Writer);

        var oid = TestUser.SuperUser.GetUserObjectId();
        var role = sp.Environments[0].Permissions.First(r => r.OId == oid);

        // Act & Assert
        Assert.ThrowsAsync<EntityReferenceException>(() => _roleController.Call_DeleteSystemPermissionRoleByIdAsync(role.Id, TestUser.Admin));
    }

    [Test]
    public async Task DeleteSystemPermissionRoleByIdAsync_WhenMultipleFullWriters_Succeeds()
    {
        // Arrange
        // permission1 -> env1: writers SuperUser, Contributor
        // permission1 -> env2: writers SuperUser, Contributor (both are full writers)
        var sp = await _permissionUtil.CreatePermission(TestUser.SuperUser, SystemPermissionUtility.GetNewSystemPermission(), _permissionUtil.StandardEnvironments);

        sp = await _permissionUtil.AssignPermissionToUser(TestUser.Contributor, sp, sp.Environments[0].Environment, SystemPermissionRoleType.Writer);
        sp = await _permissionUtil.AssignPermissionToUser(TestUser.Contributor, sp, sp.Environments[1].Environment, SystemPermissionRoleType.Writer);

        var oid = TestUser.SuperUser.GetUserObjectId();
        var role = sp.Environments[0].Permissions.First(r => r.OId == oid);

        // Act
        var result = await _roleController.Call_DeleteSystemPermissionRoleByIdAsync(role.Id, TestUser.Admin);

        // Assert
        Assert.That(result, Is.EqualTo(role.Id));
    }

    [Test]
    public async Task DeleteSystemPermissionRoleByIdAsync_ReturnsNotFound_WhenRoleDoesNotExist()
    {
        // Arrange
        var user = TestUser.SuperUser;
        SetControllerContext(_roleController, user);
        // Act
        var result = await _roleController.DeleteSystemPermissionRoleByIdAsync(99999);
        // Assert
        Assert.That(result.Result, Is.InstanceOf<NotFoundResult>());
    }

    [Test]
    public async Task UpdateSystemPermissionRoleAsync_ReturnsOk_WithUpdatedRole()
    {
        // Arrange
        var user = TestUser.SuperUser;
        var sp = await _permissionUtil.CreatePermission(user, SystemPermissionUtility.GetNewSystemPermission(), _permissionUtil.DefaultEnvironments);
        var env = sp.Environments[0];
        var oid = user.GetUserObjectId();
        var role = env.Permissions.First(r => r.OId == oid);
        var updateDto = new SystemPermissionRoleDtoUpdate
        {
            Id = role.Id,
            OId = role.OId,
            RoleType = SystemPermissionRoleType.Reader // change role type
        };
        // Act
        var result = await _roleController.Call_UpdateSystemPermissionRoleAsync(updateDto, user);
        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result.Id, Is.EqualTo(role.Id));
            Assert.That(result.RoleType, Is.EqualTo(SystemPermissionRoleType.Reader));
        }
    }

    [Test]
    public async Task UpdateSystemPermissionRoleAsync_IfMissingRole_Fails()
    {
        // Arrange
        var user = TestUser.SuperUser;
        var sp = await _permissionUtil.CreatePermission(user, SystemPermissionUtility.GetNewSystemPermission(), _permissionUtil.DefaultEnvironments);
        var env = sp.Environments[0];
        var oid = user.GetUserObjectId();
        var role = env.Permissions.First(r => r.OId == oid);
        var updateDto = new SystemPermissionRoleDtoUpdate
        {
            Id = 99999, //non-existing role id
            OId = role.OId,
            RoleType = SystemPermissionRoleType.Reader // change role type
        };

        // Act & Assert
        Assert.ThrowsAsync<EntityReferenceException>(() => _roleController.Call_UpdateSystemPermissionRoleAsync(updateDto, user));
    }
}
