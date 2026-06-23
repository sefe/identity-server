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
public class BlankPermissionSecurityTests : PermissionSecurityTestBase
{
    protected SystemPermissionController _sysController;
    protected SystemPermissionEnvironmentController _envController;
    protected SystemPermissionRoleController _roleController;

    [SetUp]
    public void Setup()
    {
        var provider = base.Setup(sc =>
        {
            sc.AddScoped<SystemPermissionController>();
            sc.AddScoped<SystemPermissionEnvironmentController>();
            sc.AddScoped<SystemPermissionRoleController>();
        });

        _sysController = provider.GetRequiredService<SystemPermissionController>();
        _envController = provider.GetRequiredService<SystemPermissionEnvironmentController>();
        _roleController = provider.GetRequiredService<SystemPermissionRoleController>();
    }

    public static IEnumerable<TestCaseData> RoleCanCreateBlankPermission
    {
        get
        {
            yield return new TestCaseData(Reader, false).SetArgDisplayNames(nameof(Reader));
            yield return new TestCaseData(Contributor, true).SetArgDisplayNames(nameof(Contributor));
            yield return new TestCaseData(Admin, true).SetArgDisplayNames(nameof(Admin));
        }
    }

    [Test]
    [TestCaseSource(nameof(RoleCanCreateBlankPermission))]
    public async Task Permission_Create_Blank(ClaimsPrincipal user, bool expectSuccess)
    {
        var blank = new SystemPermissionDtoCreate { Name = "sut", Description = "unit testing" };

        // Act
        if (expectSuccess)
        {
            var result1 = await _sysController.Call_CreateSystemPermissionAsync(blank, user);
            Assert.That(result1, Is.Not.Null);
        }
        else
        {
            Assert.ThrowsAsync<EntityAccessException>(() => _sysController.Call_CreateSystemPermissionAsync(blank, user));
        }
    }

    public static IEnumerable<TestCaseData> RoleCanDeleteBlankPermission
    {
        get
        {
            yield return new TestCaseData(Reader, false).SetArgDisplayNames(nameof(Reader));
            yield return new TestCaseData(Contributor, true).SetArgDisplayNames(nameof(Contributor));
            yield return new TestCaseData(Admin, true).SetArgDisplayNames(nameof(Admin));
        }
    }

    [Test]
    [TestCaseSource(nameof(RoleCanDeleteBlankPermission))]
    public async Task Permission_Delete_Blank(ClaimsPrincipal user, bool expectSuccess)
    {
        var blank = await CreatePermission(SuperUser, new SystemPermission { Id = 0, Name = "sut", Description = "unit testing" }, []);

        // Act
        if (expectSuccess)
        {
            var result1 = await _sysController.Call_DeleteSystemPermissionByIdAsync(blank.Id, user);
            Assert.That(result1.Value, Is.EqualTo(blank.Id));
        }
        else
        {
            Assert.ThrowsAsync<EntityAccessException>(() => _sysController.Call_DeleteSystemPermissionByIdAsync(blank.Id, user));
        }
    }

    public static IEnumerable<TestCaseData> RoleCanUpdateBlankPermission
    {
        get
        {
            yield return new TestCaseData(Reader, false).SetArgDisplayNames(nameof(Reader));
            yield return new TestCaseData(Contributor, true).SetArgDisplayNames(nameof(Contributor));
            yield return new TestCaseData(Admin, true).SetArgDisplayNames(nameof(Admin));
        }
    }

    [Test]
    [TestCaseSource(nameof(RoleCanUpdateBlankPermission))]
    public async Task Permission_Update_Blank(ClaimsPrincipal user, bool expectSuccess)
    {
        var blank = await CreatePermission(SuperUser, new SystemPermission { Id = 0, Name = "sut", Description = "unit testing" }, []);
        var updatedDescription = "updated description";

        // Act
        var updateDto = new SystemPermissionDtoUpdate { Id = blank.Id, Description = updatedDescription };

        // Assert
        if (expectSuccess)
        {
            var result1 = await _sysController.Call_UpdateSystemPermissionAsync(updateDto, user);
            using (Assert.EnterMultipleScope())
            {
                Assert.That(result1.Id, Is.EqualTo(blank.Id));
                Assert.That(result1.Description, Is.EqualTo(updatedDescription));
            }
        }
        else
        {
            Assert.ThrowsAsync<EntityAccessException>(() => _sysController.Call_UpdateSystemPermissionAsync(updateDto, user));
        }
    }

    public static IEnumerable<TestCaseData> RoleCanReadBlankPermission
    {
        get
        {
            yield return new TestCaseData(Reader, false).SetArgDisplayNames(nameof(Reader));
            yield return new TestCaseData(Contributor, true).SetArgDisplayNames(nameof(Contributor));
            yield return new TestCaseData(Admin, true).SetArgDisplayNames(nameof(Admin));
        }
    }

    [Test]
    [TestCaseSource(nameof(RoleCanReadBlankPermission))]
    public async Task Permission_ReadById_CanSeeBlank_WithNoEnvironments(ClaimsPrincipal user, bool expectSuccess)
    {
        var blank = await CreatePermission(SuperUser, new SystemPermission { Id = 0, Name = "sut", Description = "unit testing" }, []);

        // Act
        if (expectSuccess)
        {
            var result1 = await _sysController.Call_GetSystemPermissionByIdAsync(blank.Id, user);
            // Assert
            using (Assert.EnterMultipleScope())
            {
                Assert.That(result1, Is.Not.Null);
                Assert.That(result1.Id, Is.EqualTo(blank.Id));
            }
        }
        else
        {
            Assert.ThrowsAsync<EntityAccessException>(() => _sysController.Call_GetSystemPermissionByIdAsync(blank.Id, user));
        }
    }

    [Test]
    [TestCaseSource(nameof(RoleCanReadBlankPermission))]
    public async Task Permission_ReadAll_CanSeeBlank_WithNoEnvironments(ClaimsPrincipal user, bool expectSuccess)
    {
        var blank = await CreatePermission(SuperUser, new SystemPermission { Id = 0, Name = "sut", Description = "unit testing" }, []);

        // Act
        var result1 = await _sysController.Call_GetSystemPermissionsPagedAsync(user);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result1, Is.Not.Null);
            Assert.That(result1, Has.Count.EqualTo(1));
            Assert.That(result1[0].Id, Is.EqualTo(blank.Id));
            if (expectSuccess)
            {
                Assert.That(result1[0].AccessLevel, Is.EqualTo(SystemPermissionRoleType.Writer));
            }
            else
            {
                Assert.That(result1[0].AccessLevel, Is.EqualTo(SystemPermissionRoleType.None));
            }
        }
    }

    public static IEnumerable<TestCaseData> RoleCanCreatePermissionEnvironmentForBlankPermission
    {
        get
        {
            yield return new TestCaseData(Reader, false).SetArgDisplayNames(nameof(Reader));
            yield return new TestCaseData(Contributor, true).SetArgDisplayNames(nameof(Contributor));
            yield return new TestCaseData(Admin, true).SetArgDisplayNames(nameof(Admin));
        }
    }

    [Test]
    [TestCaseSource(nameof(RoleCanCreatePermissionEnvironmentForBlankPermission))]
    public async Task PermissionEnvironment_Create_ForBlankPermission(ClaimsPrincipal user, bool expectSuccess)
    {
        // Arrange
        var blank = await CreatePermission(SuperUser, new SystemPermission { Id = 0, Name = "sut", Description = "unit testing" }, []);

        // do not assign any permissions

        var newEnvironment = new SystemPermissionEnvironmentDtoCreate
        {
            Environment = SystemPermissionEnvironmentNames.EnvironmentNames.First(),
            SystemPermissionId = blank.Id,
        };

        // Act
        if (expectSuccess)
        {
            var result1 = await _envController.Call_CreateSystemPermissionEnvironmentAsync(newEnvironment, user);
            // Assert
            using (Assert.EnterMultipleScope())
            {
                Assert.That(result1.Id, Is.EqualTo(blank.Id));
                Assert.That(result1.Environments, Has.Count.EqualTo(1));
                foreach (var env in result1.Environments)
                {
                    Assert.That(env.Id, Is.Not.Zero);
                    Assert.That(env.SystemPermissionId, Is.EqualTo(blank.Id));
                    //newly created env must have creator assigned as Writer
                    Assert.That(env.Permissions, Has.Count.EqualTo(1));
                    Assert.That(env.Permissions.FirstOrDefault().Id, Is.Not.Zero);
                    Assert.That(env.Permissions.FirstOrDefault().Name, Is.EqualTo(user.Identity.Name));
                    Assert.That(env.Permissions.FirstOrDefault().RoleType, Is.EqualTo(SystemPermissionRoleType.Writer));
                }
            }
        }
        else
        {
            Assert.ThrowsAsync<EntityAccessException>(() => _envController.Call_CreateSystemPermissionEnvironmentAsync(newEnvironment, user));
        }
    }
}
