// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

using System.Linq.Expressions;
using System.Security.Claims;
using NSubstitute;
using IdentityServer.Abstraction.Contracts;
using IdentityServer.Abstraction.Entities.IdentityServerConfig.SystemPermissions;
using IdentityServer.Abstraction.Exceptions;
using IdentityServer.Data.Security;
using IdentityServer.Tests.Common.Builders;
using static IdentityServer.Abstraction.Constants;

namespace IdentityServer.Data.Test.Security;

[TestFixture]
public class StandardPermissionCheckerTests
{
    private IStorage<SystemPermissionRole> _roleStorage;
    private IStorage<SystemPermissionEnvironment> _envStorage;
    private StandardPermissionChecker _permissionChecker;

    private readonly Claim _adminRole = new(ClaimTypes.Role, RoleNames.Admin);
    private readonly Claim _readerRole = new(ClaimTypes.Role, RoleNames.Reader);
    private readonly Claim _userRole = new(ClaimTypes.Role, RoleNames.User);
    private static Claim CreateOidClaim(string id) => new(ClaimNames.UserObjectId, id);

    [SetUp]
    public void SetUp()
    {
        _roleStorage = Substitute.For<IStorage<SystemPermissionRole>>();
        _envStorage = Substitute.For<IStorage<SystemPermissionEnvironment>>();
        _permissionChecker = new StandardPermissionChecker(_roleStorage, _envStorage);

        var roles = new List<SystemPermissionRole>
        {
            new() { SystemPermissionEnvironmentId = 1, OId = "user1", Name = "user11", RoleType = SystemPermissionRoleType.Reader},
            new() { SystemPermissionEnvironmentId = 2, OId = "user1", Name = "user11", RoleType = SystemPermissionRoleType.Writer},
            new() { SystemPermissionEnvironmentId = 3, OId = "user2", Name = "user22", RoleType = SystemPermissionRoleType.Reader},
            new() { SystemPermissionEnvironmentId = 4, OId = "user2", Name = "user22", RoleType = SystemPermissionRoleType.Reader},
        };
        _roleStorage.ToListAsync(Arg.Any<Expression<Func<SystemPermissionRole, bool>>>())
            .Returns(call =>
            {
                var expression = call.Arg<Expression<Func<SystemPermissionRole, bool>>>();
                if (expression == null)
                {
                    return roles;
                }

                var compiledExpression = expression.Compile();
                return roles.Where(compiledExpression).ToList();
            });
    }

    #region GetAllAccessiblePermissionEnvironments
    [TestCase(SystemPermissionRoleType.Reader)]
    [TestCase(SystemPermissionRoleType.Writer)]
    public async Task GetAllAccessiblePermissionEnvironmentsAsync_AdminRole_ReturnsAllEnvironments(SystemPermissionRoleType role)
    {
        // Arrange
        var user = new ClaimsPrincipal(new ClaimsIdentity(new[] { _adminRole }));
        var sp = new SystemPermissionBuilder().Build();
        var environments = new List<SystemPermissionEnvironment>
        {
            new() { Id = 1, Environment = "111", SystemPermission = sp },
            new() { Id = 2, Environment = "222", SystemPermission = sp }
        };
        _envStorage.ToListAsync(Arg.Any<Expression<Func<SystemPermissionEnvironment, bool>>>())
            .Returns(environments);

        // Act
        var result = await _permissionChecker.GetAllAccessiblePermissionEnvironmentsAsync(user, role);

        // Assert
        Assert.That(result, Is.EquivalentTo(new HashSet<int> { 1, 2 }));
    }

    [Test]
    public async Task GetAllAccessiblePermissionEnvironmentsAsync_NonAdminRoleReader_ReturnsFilteredEnvironments()
    {
        // Arrange
        var user = new ClaimsPrincipal(new ClaimsIdentity(new[] { CreateOidClaim("user1") }));

        // Act
        var result = await _permissionChecker.GetAllAccessiblePermissionEnvironmentsAsync(user, SystemPermissionRoleType.Reader);

        // Assert
        Assert.That(result, Is.EquivalentTo(new HashSet<int> { 1, 2 }));
    }

    [Test]
    public async Task GetAllAccessiblePermissionEnvironmentsAsync_NonAdminRoleWriter_ReturnsFilteredEnvironments()
    {
        // Arrange
        var user = new ClaimsPrincipal(new ClaimsIdentity(new[] { CreateOidClaim("user1") }));

        // Act
        var result = await _permissionChecker.GetAllAccessiblePermissionEnvironmentsAsync(user, SystemPermissionRoleType.Writer);

        // Assert
        Assert.That(result, Is.EquivalentTo(new HashSet<int> { 2 }));
    }

    [Test]
    public void GetAllAccessiblePermissionEnvironmentsAsync_NonAdminRoleWrongRole_ThrowsException()
    {
        // Arrange
        var user = new ClaimsPrincipal(new ClaimsIdentity(new[] { CreateOidClaim("user1") }));

        // Act & Assert
        Assert.ThrowsAsync<NotImplementedException>(async () =>
            await _permissionChecker.GetAllAccessiblePermissionEnvironmentsAsync(user, SystemPermissionRoleType.None));
    }

    #endregion

    private static readonly SystemPermissionRole _defaultUserReaderRole = new()
    {
        Id = 1,
        OId = "user",
        Name = "user",
        RoleType = SystemPermissionRoleType.Reader,
    };

    private static readonly SystemPermissionRole _defaultUserWriterRole = new()
    {
        Id = 2,
        OId = "user",
        Name = "user",
        RoleType = SystemPermissionRoleType.Writer,
    };

    private static readonly SystemPermissionRole _randomUserReaderRole = new()
    {
        Id = 3,
        OId = "randomUser",
        Name = "randomUser",
        RoleType = SystemPermissionRoleType.Reader,
    };

    private static readonly SystemPermissionRole _randomUserWriterRole = new()
    {
        Id = 4,
        OId = "randomUser",
        Name = "randomUser",
        RoleType = SystemPermissionRoleType.Writer,
    };

    #region ThrowIfNoAccessToEnv

    [TestCase(EntityAccessType.Create)]
    [TestCase(EntityAccessType.Read)]
    [TestCase(EntityAccessType.Update)]
    [TestCase(EntityAccessType.Delete)]
    public async Task GetAccessRoleOrThrowIfNoAccessToEnvAsync_AdminRole_ReturnsWriterRole(EntityAccessType accessType)
    {
        // Arrange
        var user = new ClaimsPrincipal(new ClaimsIdentity(new[] { _adminRole }));

        // Act
        var result = await _permissionChecker.GetAccessRoleOrThrowIfNoAccessToEnvAsync(user, 1, accessType, "TestItem");

        // Assert
        Assert.That(result, Is.EqualTo(SystemPermissionRoleType.Writer));
    }

    [TestCase(EntityAccessType.Create)]
    [TestCase(EntityAccessType.Update)]
    [TestCase(EntityAccessType.Delete)]
    public void GetAccessRoleOrThrowIfNoAccessToEnvAsync_ReaderRole_OnWriteOperation_ThrowsException(EntityAccessType accessType)
    {
        // Arrange
        var user = new ClaimsPrincipal(new ClaimsIdentity(new[] { CreateOidClaim("user1"), _readerRole }));

        // Act & Assert
        var ex = Assert.ThrowsAsync<EntityAccessException>(async () =>
            await _permissionChecker.GetAccessRoleOrThrowIfNoAccessToEnvAsync(user, 1, accessType, "TestItem"));
        Assert.That(ex!.Message, Does.Contain("user1"));
    }

    [Test]
    public async Task GetAccessRoleOrThrowIfNoAccessToEnvAsync_ReaderRole_WithReadSystemPermissionsOnReadOperation_ReturnsReader()
    {
        // Arrange
        var user = new ClaimsPrincipal(new ClaimsIdentity(new[] { CreateOidClaim("user"), _readerRole }));
        var sysPermission = new SystemPermissionBuilder()
            .AddEnvironment(1, "1", new List<SystemPermissionRole> { _defaultUserReaderRole })
            .Build();
        var env1 = sysPermission.Environments.First(e => e.Id == 1);

        _roleStorage.ToListAsync(Arg.Any<Expression<Func<SystemPermissionRole, bool>>>())
            .Returns(_ => new List<SystemPermissionRole>() { _defaultUserReaderRole });
        _envStorage.GetByIdAsync(env1.Id).Returns(env1);

        // Act
        var result = await _permissionChecker.GetAccessRoleOrThrowIfNoAccessToEnvAsync(user, 1, EntityAccessType.Read, "target");

        // Assert
        Assert.That(result, Is.EqualTo(SystemPermissionRoleType.Reader));
    }

    [Test]
    public void GetAccessRoleOrThrowIfNoAccessToEnvAsync_ReaderRole_NoSystemPermissionsOnReadOperation_ThrowsException()
    {
        // Arrange
        var user = new ClaimsPrincipal(new ClaimsIdentity(new[] { CreateOidClaim("user"), _readerRole }));
        var sysPermission = new SystemPermissionBuilder()
            .AddEnvironment(1, "1", new List<SystemPermissionRole>() { _randomUserWriterRole })
            .Build();
        var env1 = sysPermission.Environments.First(e => e.Id == 1);

        _roleStorage.ToListAsync(Arg.Any<Expression<Func<SystemPermissionRole, bool>>>())
            .Returns(_ => new List<SystemPermissionRole>());
        _envStorage.GetByIdAsync(env1.Id)
            .Returns(env1);

        // Act & Assert
        var ex = Assert.ThrowsAsync<EntityAccessException>(async () =>
            await _permissionChecker.GetAccessRoleOrThrowIfNoAccessToEnvAsync(user, 1, EntityAccessType.Read, "custom text"));
        Assert.That(ex!.Message, Does.Contain($"Restricted system permission environment id: '{env1.Id}'."));
    }

    [TestCase(EntityAccessType.Create)]
    [TestCase(EntityAccessType.Read)]
    [TestCase(EntityAccessType.Update)]
    [TestCase(EntityAccessType.Delete)]
    public void GetAccessRoleOrThrowIfNoAccessToEnvAsync_UserRole_WithNoSystemPermissionsOnAnyOperation_ThrowsException(EntityAccessType accessType)
    {
        // Arrange
        // SPE1 belongs to SP11, SPE2 belongs to SP11, SPE2 has some other permissions
        var user = new ClaimsPrincipal(new ClaimsIdentity(new[] { CreateOidClaim("user"), _userRole }));
        var sysPermission = new SystemPermissionBuilder()
            .AddEnvironment(1, "1", new List<SystemPermissionRole>() { _randomUserWriterRole })
            .AddEnvironment(3, "3", new List<SystemPermissionRole> { _randomUserReaderRole })
            .Build();
        var env1 = sysPermission.Environments.First(e => e.Id == 1);
        _roleStorage.ToListAsync(Arg.Any<Expression<Func<SystemPermissionRole, bool>>>())
            .Returns(_ => new List<SystemPermissionRole>());
        _envStorage.GetByIdAsync(env1.Id).Returns(env1);

        // Act & Assert
        var ex = Assert.ThrowsAsync<EntityAccessException>(async () =>
            await _permissionChecker.GetAccessRoleOrThrowIfNoAccessToEnvAsync(user, 1, accessType, "target"));

        Assert.That(ex!.Message, Does.Contain($"Restricted system permission environment id: '{env1.Id}'."));
    }

    // not covered transitive cases when no direct permissions present: GetAccessRoleOrThrowIfNoAccessToEnvAsync with User on Reader, Partial Writer, Full Writer on the SystemPermission

    #endregion

    #region GetAccessRoleOrThrowIfNoAccessToSystemAsync

    [TestCase(EntityAccessType.Create)]
    [TestCase(EntityAccessType.Read)]
    [TestCase(EntityAccessType.Update)]
    [TestCase(EntityAccessType.Delete)]
    public void GetAccessRoleOrThrowIfNoAccessToSystemAsync_AdminRole_ReturnsWriterRole(EntityAccessType accessType)
    {
        // Arrange
        var user = new ClaimsPrincipal(new ClaimsIdentity(new[] { CreateOidClaim("admin"), _adminRole }));
        var system = new SystemPermission() { Name = "name", Description = "desc" };

        // Act
        var result = _permissionChecker.GetAccessRoleOrThrowIfNoAccessToSystem(user, system, accessType, "TestItem");

        // Assert
        Assert.That(result, Is.EqualTo(SystemPermissionRoleType.Writer));
    }

    [TestCase(EntityAccessType.Create)]
    [TestCase(EntityAccessType.Read)]
    [TestCase(EntityAccessType.Update)]
    [TestCase(EntityAccessType.Delete)]
    public void GetAccessRoleOrThrowIfNoAccessToSystemAsync_UserRole_WithNoSystemPermissionsOnAnyOperation_ThrowsException(EntityAccessType accessType)
    {
        // Arrange
        // SPE1 belongs to SP11, SPE2 belongs to SP11, SPE2 has some other permissions
        var user = new ClaimsPrincipal(new ClaimsIdentity(new[] { CreateOidClaim("user"), _userRole }));
        var sysPermission = new SystemPermissionBuilder()
            .AddEnvironment(3, "3", new List<SystemPermissionRole> { _randomUserReaderRole })
            .Build();

        // Act & Assert
        var ex = Assert.Throws<EntityAccessException>(() =>
            _permissionChecker.GetAccessRoleOrThrowIfNoAccessToSystem(user, sysPermission, accessType, "target"));

        Assert.That(ex!.Message, Does.Contain($"Restricted system permission id: '{sysPermission.Id}'."));
    }

    [TestCase(EntityAccessType.Create)]
    [TestCase(EntityAccessType.Update)]
    [TestCase(EntityAccessType.Delete)]
    public void GetAccessRoleOrThrowIfNoAccessToSystemAsync_UserRole_WithReaderSystemPermissionsOnWriteOperation_ThrowsException(EntityAccessType accessType)
    {
        // Arrange
        // SPE1 belongs to SP11, SPE2 belongs to SP11, SPE2 has some other permissions
        var user = new ClaimsPrincipal(new ClaimsIdentity(new[] { CreateOidClaim("user"), _userRole }));
        var sysPermission = new SystemPermissionBuilder()
            .AddEnvironment(1, "1", new List<SystemPermissionRole> { _defaultUserReaderRole })
            .Build();

        // Act & Assert
        var ex = Assert.Throws<EntityAccessException>(() =>
            _permissionChecker.GetAccessRoleOrThrowIfNoAccessToSystem(user, sysPermission, accessType, "target"));

        Assert.That(ex!.Message, Does.Contain($"Restricted system permission id: '{sysPermission.Id}'."));
    }

    [Test]
    public void GetAccessRoleOrThrowIfNoAccessToSystemAsync_UserRole_WithReaderSystemPermissionsOnReadOperation_ReturnsReader()
    {
        // Arrange
        var user = new ClaimsPrincipal(new ClaimsIdentity(new[] { CreateOidClaim("user"), _userRole }));
        var sp = new SystemPermissionBuilder()
            .AddEnvironment(1, "1", new List<SystemPermissionRole> { _defaultUserReaderRole })
            .Build();

        // Act
        var result = _permissionChecker.GetAccessRoleOrThrowIfNoAccessToSystem(user, sp, EntityAccessType.Read, "target");

        // Assert
        Assert.That(result, Is.EqualTo(SystemPermissionRoleType.Reader));
    }

    [Test]
    public void GetAccessRoleOrThrowIfNoAccessToSystemAsync_UserRole_WithPartialWriterSystemPermissionsOnReadOperation_ReturnsReader()
    {
        // Arrange
        var user = new ClaimsPrincipal(new ClaimsIdentity(new[] { CreateOidClaim("user"), _userRole }));
        var sp = new SystemPermissionBuilder()
            .AddEnvironment(1, "1", new List<SystemPermissionRole> { _defaultUserReaderRole })
            .AddEnvironment(2, "2", new List<SystemPermissionRole> { _defaultUserWriterRole })
            .Build();

        // Act
        var result = _permissionChecker.GetAccessRoleOrThrowIfNoAccessToSystem(user, sp, EntityAccessType.Read, "target");

        // Assert
        Assert.That(result, Is.EqualTo(SystemPermissionRoleType.Reader));
    }

    [TestCase(EntityAccessType.Create)]
    [TestCase(EntityAccessType.Update)]
    [TestCase(EntityAccessType.Delete)]
    public void GetAccessRoleOrThrowIfNoAccessToSystemAsync_UserRole_WithPartialWriterSystemPermissionOnWriteOperation_ThrowsException(EntityAccessType accessType)
    {
        // Arrange
        var user = new ClaimsPrincipal(new ClaimsIdentity(new[] { CreateOidClaim("user"), _userRole }));
        var sp = new SystemPermissionBuilder()
            .AddEnvironment(1, "1", new List<SystemPermissionRole> { _defaultUserReaderRole })
            .AddEnvironment(2, "2", new List<SystemPermissionRole> { _defaultUserWriterRole })
            .Build();

        // Act & Assert
        var ex = Assert.Throws<EntityAccessException>(() =>
            _permissionChecker.GetAccessRoleOrThrowIfNoAccessToSystem(user, sp, accessType, "target"));

        Assert.That(ex!.Message, Does.Contain($"Restricted system permission id: '{sp.Id}'."));

    }

    [TestCase(EntityAccessType.Create)]
    [TestCase(EntityAccessType.Read)]
    [TestCase(EntityAccessType.Update)]
    [TestCase(EntityAccessType.Delete)]
    public void GetAccessRoleOrThrowIfNoAccessToSystemAsync_UserRole_WithFullWriterSystemPermissionOnAnyOperation_ReturnsWriter(EntityAccessType accessType)
    {
        // Arrange
        var user = new ClaimsPrincipal(new ClaimsIdentity(new[] { CreateOidClaim("user"), _userRole }));
        var sp = new SystemPermissionBuilder()
            .AddEnvironment(2, "2", new List<SystemPermissionRole> { _defaultUserWriterRole })
            .Build();

        // Act
        var result = _permissionChecker.GetAccessRoleOrThrowIfNoAccessToSystem(user, sp, accessType, "target");

        // Assert
        Assert.That(result, Is.EqualTo(SystemPermissionRoleType.Writer));
    }

    [Test]
    public void GetAccessRoleOrThrowIfNoAccessToSystemAsync_ReaderRole_WithSystemPermissionsOnReadOperation_ReturnsReader()
    {
        // Arrange
        var user = new ClaimsPrincipal(new ClaimsIdentity(new[] { CreateOidClaim("user"), _readerRole }));
        var sysPermission = new SystemPermissionBuilder()
            .AddEnvironment(1, "1", new List<SystemPermissionRole> { _defaultUserReaderRole })
            .Build();

        // Act
        var result = _permissionChecker.GetAccessRoleOrThrowIfNoAccessToSystem(user, sysPermission, EntityAccessType.Read, "target");

        // Assert
        Assert.That(result, Is.EqualTo(SystemPermissionRoleType.Reader));
    }

    [TestCase(EntityAccessType.Create)]
    [TestCase(EntityAccessType.Update)]
    [TestCase(EntityAccessType.Delete)]
    public void GetAccessRoleOrThrowIfNoAccessToSystemAsync_ReaderRole_OnWriteOperation_ThrowsException(EntityAccessType accessType)
    {
        // Arrange
        // SPE1 belongs to SP11, SPE2 belongs to SP11, SPE2 has some other permissions
        var user = new ClaimsPrincipal(new ClaimsIdentity(new[] { CreateOidClaim("user"), _readerRole }));
        var sysPermission = new SystemPermissionBuilder()
            .AddEnvironment(2, "2", new List<SystemPermissionRole> { _defaultUserReaderRole })
            .Build();

        // Act & Assert
        var ex = Assert.Throws<EntityAccessException>(() =>
            _permissionChecker.GetAccessRoleOrThrowIfNoAccessToSystem(user, sysPermission, accessType, "target"));

        Assert.That(ex!.Message, Does.Contain($"Restricted system permission id: '{sysPermission.Id}'."));
    }

    [Test]
    public void GetAccessRoleOrThrowIfNoAccessToSystemAsync_ReaderRole_WithNoSystemPermissionsOnReadOperation_ThrowsException()
    {
        // Arrange
        // SPE1 belongs to SP11, SPE2 belongs to SP11, SPE2 has some other permissions
        var user = new ClaimsPrincipal(new ClaimsIdentity(new[] { CreateOidClaim("user"), _readerRole }));
        var sysPermission = new SystemPermissionBuilder()
            .AddEnvironment(2, "2", new List<SystemPermissionRole>() { _randomUserWriterRole })
            .Build();

        // Act & Assert
        var ex = Assert.Throws<EntityAccessException>(() =>
            _permissionChecker.GetAccessRoleOrThrowIfNoAccessToSystem(user, sysPermission, EntityAccessType.Read, "target"));

        Assert.That(ex!.Message, Does.Contain($"Restricted system permission id: '{sysPermission.Id}'."));
    }

    #endregion
}
