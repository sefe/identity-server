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
public class PermissionEnvironmentSecurityTests : PermissionSecurityTestBase
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

    public static IEnumerable<TestCaseData> RoleCanCreatePermissionEnvironmentIfAssigned
    {
        get
        {
            yield return new TestCaseData(Reader, "None", false).SetArgDisplayNames(nameof(Reader), "None");
            yield return new TestCaseData(Reader, "Reader", false).SetArgDisplayNames(nameof(Reader), "Reader");
            yield return new TestCaseData(Reader, "PartialWriter", false).SetArgDisplayNames(nameof(Reader), "PartialWriter");
            yield return new TestCaseData(Reader, "FullWriter", false).SetArgDisplayNames(nameof(Reader), "FullWriter");
            yield return new TestCaseData(Contributor, "None", false).SetArgDisplayNames(nameof(Contributor), "None");
            yield return new TestCaseData(Contributor, "Reader", false).SetArgDisplayNames(nameof(Contributor), "Reader");
            yield return new TestCaseData(Contributor, "PartialWriter", false).SetArgDisplayNames(nameof(Contributor), "PartialWriter");
            yield return new TestCaseData(Contributor, "FullWriter", true).SetArgDisplayNames(nameof(Contributor), "FullWriter");
            yield return new TestCaseData(Admin, "None", true).SetArgDisplayNames(nameof(Admin));
        }
    }

    [Test]
    [TestCaseSource(nameof(RoleCanCreatePermissionEnvironmentIfAssigned))]
    public async Task Permission_Environment_Create(ClaimsPrincipal user, string assignments, bool expectSuccess)
    {
        // Arrange
        await CreateDefaultPermissionInfrastructure_With1Permission_And2Environments();

        switch (assignments)
        {
            case "None":
                break;
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
        var newEnvName = SystemPermissionEnvironmentNames.EnvironmentNames.First(e => !_permission1.Environments.Any(pe => pe.Environment == e));

        // Act
        var newEnvironment = new SystemPermissionEnvironmentDtoCreate
        {
            Environment = newEnvName,
            SystemPermissionId = _permission1.Id,
        };

        if (expectSuccess)
        {
            var result1 = await _envController.Call_CreateSystemPermissionEnvironmentAsync(newEnvironment, user);

            // Assert
            using (Assert.EnterMultipleScope())
            {
                Assert.That(result1.Id, Is.EqualTo(_permission1.Id));
                Assert.That(result1.Environments, Has.Count.EqualTo(_permission1.Environments.Count + 1));
                foreach (var e in result1.Environments.Where(ne => !_permission1.Environments.Any(ee => ee.Environment == ne.Environment)))
                {
                    Assert.That(e.Id, Is.Not.Zero);
                    //newly created env must have creator assigned as Writer
                    Assert.That(e.Permissions, Has.Count.EqualTo(1));
                    Assert.That(e.Permissions.Any(pe => pe.Id != 0 && pe.Name == user.Identity.Name && pe.RoleType == SystemPermissionRoleType.Writer), Is.True);
                }
            }
        }
        else
        {
            Assert.ThrowsAsync<EntityAccessException>(() => _envController.Call_CreateSystemPermissionEnvironmentAsync(newEnvironment, user));
        }
    }

    public static IEnumerable<TestCaseData> RoleCanDeletePermissionEnvironment
    {
        get
        {
            yield return new TestCaseData(Reader, "None", false).SetArgDisplayNames(nameof(Reader), "None");
            yield return new TestCaseData(Reader, "Reader", false).SetArgDisplayNames(nameof(Reader), "Reader");
            yield return new TestCaseData(Reader, "PartialWriter", false).SetArgDisplayNames(nameof(Reader), "PartialWriter");
            yield return new TestCaseData(Reader, "FullWriter", false).SetArgDisplayNames(nameof(Reader), "FullWriter");
            yield return new TestCaseData(Contributor, "None", false).SetArgDisplayNames(nameof(Contributor), "None");
            yield return new TestCaseData(Contributor, "Reader", false).SetArgDisplayNames(nameof(Contributor), "Reader");
            yield return new TestCaseData(Contributor, "PartialWriter", true).SetArgDisplayNames(nameof(Contributor), "PartialWriter");
            yield return new TestCaseData(Contributor, "FullWriter", true).SetArgDisplayNames(nameof(Contributor), "FullWriter");
            yield return new TestCaseData(Admin, "None", true).SetArgDisplayNames(nameof(Admin));
        }
    }

    [Test]
    [TestCaseSource(nameof(RoleCanDeletePermissionEnvironment))]
    public async Task DeletePermissionEnvironment_DependsOnRole(ClaimsPrincipal user, string assignments, bool expectSuccess)
    {
        // Arrange
        await CreateDefaultPermissionInfrastructure_With1Permission_And2Environments();

        switch (assignments)
        {
            case "None":
                break;
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
        var envToRemove = _permission1.Environments[0];

        if (expectSuccess)
        {
            var result1 = await _envController.Call_DeleteSystemPermissionEnvironmentByIdAsync(envToRemove.Id, user);
            // Assert
            Assert.That(result1, Is.EqualTo(envToRemove.Id));
        }
        else
        {
            Assert.ThrowsAsync<EntityAccessException>(() => _envController.Call_DeleteSystemPermissionEnvironmentByIdAsync(envToRemove.Id, user));
        }
    }

    public static IEnumerable<TestCaseData> RoleCanCreatePermissionEnvironmentAssignments
    {
        get
        {
            yield return new TestCaseData(Reader, "None", false).SetArgDisplayNames(nameof(Reader), "None");
            yield return new TestCaseData(Reader, "Reader", false).SetArgDisplayNames(nameof(Reader), "Reader");
            yield return new TestCaseData(Reader, "PartialWriter", false).SetArgDisplayNames(nameof(Reader), "PartialWriter");
            yield return new TestCaseData(Reader, "FullWriter", false).SetArgDisplayNames(nameof(Reader), "FullWriter");
            yield return new TestCaseData(Contributor, "None", false).SetArgDisplayNames(nameof(Contributor), "None");
            yield return new TestCaseData(Contributor, "Reader", false).SetArgDisplayNames(nameof(Contributor), "Reader");
            yield return new TestCaseData(Contributor, "PartialWriter", true).SetArgDisplayNames(nameof(Contributor), "PartialWriter");
            yield return new TestCaseData(Contributor, "FullWriter", true).SetArgDisplayNames(nameof(Contributor), "FullWriter");
            yield return new TestCaseData(Admin, "None", true).SetArgDisplayNames(nameof(Admin));
        }
    }

    [Test]
    [TestCaseSource(nameof(RoleCanCreatePermissionEnvironmentAssignments))]
    public async Task CreateRole_DependsOnPermissions(ClaimsPrincipal user, string assignments, bool expectSuccess)
    {
        // Arrange
        await CreateDefaultPermissionInfrastructure_With1Permission_And2Environments();

        switch (assignments)
        {
            case "None":
                break;
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

        var expectedUser = CreateRandomReaderUser();

        var assignment1 = new SystemPermissionRoleDtoCreate
        {
            SystemPermissionEnvironmentId = _permission1.Environments[0].Id,
            RoleType = SystemPermissionRoleType.Reader,
            OId = expectedUser.OId,
        };

        // Act
        if (expectSuccess)
        {
            var result1 = await _roleController.Call_CreateSystemPermissionRoleAsync(assignment1, user);
            // Assert
            using (Assert.EnterMultipleScope())
            {
                Assert.That(result1.Id, Is.Not.Zero);
                Assert.That(result1.OId, Is.EqualTo(expectedUser.OId));
                Assert.That(result1.Name, Is.EqualTo(expectedUser.DisplayName));
                Assert.That(result1.RoleType, Is.EqualTo(assignment1.RoleType));
            }
        }
        else
        {
            Assert.ThrowsAsync<EntityAccessException>(() => _roleController.Call_CreateSystemPermissionRoleAsync(assignment1, user));
        }
    }

    public static IEnumerable<TestCaseData> RoleCanDeletePermissionEnvironmentAssignments
    {
        get
        {
            yield return new TestCaseData(Reader, "None", false, typeof(EntityAccessException)).SetArgDisplayNames(nameof(Reader), "None");
            yield return new TestCaseData(Reader, "Reader", false, typeof(EntityAccessException)).SetArgDisplayNames(nameof(Reader), "Reader");
            yield return new TestCaseData(Reader, "PartialWriter", false, typeof(EntityAccessException)).SetArgDisplayNames(nameof(Reader), "PartialWriter");
            yield return new TestCaseData(Reader, "FullWriter", false, typeof(EntityAccessException)).SetArgDisplayNames(nameof(Reader), "FullWriter");
            yield return new TestCaseData(Contributor, "None", false, typeof(EntityAccessException)).SetArgDisplayNames(nameof(Contributor), "None");
            yield return new TestCaseData(Contributor, "Reader", false, typeof(EntityAccessException)).SetArgDisplayNames(nameof(Contributor), "Reader");
            yield return new TestCaseData(Contributor, "PartialWriter", false, typeof(EntityReferenceException)).SetArgDisplayNames(nameof(Contributor), "PartialWriter");
            yield return new TestCaseData(Contributor, "FullWriter", true, typeof(EntityAccessException)).SetArgDisplayNames(nameof(Contributor), "FullWriter");
            yield return new TestCaseData(Admin, "None", false, typeof(EntityReferenceException)).SetArgDisplayNames(nameof(Admin));
        }
    }

    [Test]
    [TestCaseSource(nameof(RoleCanDeletePermissionEnvironmentAssignments))]
    public async Task DeleteRole_DependsOnPermissions(ClaimsPrincipal user, string assignments, bool expectSuccess, Type exceptionType)
    {
        // Arrange
        await CreateDefaultPermissionInfrastructure_With1Permission_And2Environments();
        await AssignPermissionToUser(Contributor2, _permission1, _permission1.Environments[0].Environment, SystemPermissionRoleType.Writer); // ensure 2 writers for the environment

        switch (assignments)
        {
            case "None":
                break;
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
        var permissionToDelete = _permission1.Environments[0].Permissions[0];

        // Act & Assert
        if (expectSuccess)
        {
            var result1 = await _roleController.Call_DeleteSystemPermissionRoleByIdAsync(permissionToDelete.Id, user);
            Assert.That(result1, Is.EqualTo(permissionToDelete.Id));
        }
        else
        {
            Assert.ThrowsAsync(Is.TypeOf(exceptionType), () => _roleController.Call_DeleteSystemPermissionRoleByIdAsync(permissionToDelete.Id, user));
        }
    }
}
