using System.Linq.Expressions;
using System.Security.Claims;
using AutoMapper;
using NSubstitute;
using IdentityServer.Abstraction.Contracts;
using IdentityServer.Abstraction.Entities.IdentityServerConfig.SystemPermissions;
using IdentityServer.Data.DuendeEntityExtensions;
using IdentityServer.Data.Repositories.DtoRepositories;
using IdentityServer.Tests.Common.Builders;

namespace IdentityServer.Data.Test.Repositories;

[TestFixture]
public class SystemPermissionDtoRepositoryTests
{
    private IStorage<SystemPermission> _systemPermissionStorageMock;
    private IStorage<ClientExt> _clientStorageMock;
    private IStorage<ApiResourceExt> _apiResourceStorageMock;
    private IMapper _mapperMock;
    private IPermissionChecker _permissionCheckerMock;
    private ISystemPermissionAuditService _auditServiceMock;
    private SystemPermissionDtoRepository _sut;
    private ClaimsPrincipal _user;

    [SetUp]
    public void SetUp()
    {
        _systemPermissionStorageMock = Substitute.For<IStorage<SystemPermission>>();
        _clientStorageMock = Substitute.For<IStorage<ClientExt>>();
        _apiResourceStorageMock = Substitute.For<IStorage<ApiResourceExt>>();
        _mapperMock = Substitute.For<IMapper>();
        _permissionCheckerMock = Substitute.For<IPermissionChecker>();
        _auditServiceMock = Substitute.For<ISystemPermissionAuditService>();

        _sut = new SystemPermissionDtoRepository(
            _systemPermissionStorageMock,
            _clientStorageMock,
            _apiResourceStorageMock,
            _mapperMock,
            _permissionCheckerMock,
            _auditServiceMock);

        _user = new ClaimsPrincipal();
    }

    [Test]
    public async Task DeleteAsync_WithNestedEntities_UpdatesAuditFieldsRecursively()
    {
        // Arrange
        var testSystemPermission = new SystemPermissionBuilder()
            .WithId(1)
            .WithName("test-system-permission")
            .WithDescription("Test System Permission")
            .AddEnvironment(1, SystemPermissionEnvironmentNames.Development, new List<SystemPermissionRole>
            {
                new() { Id = 1, SystemPermissionEnvironmentId = 1, OId = "user1", Name = "User 1", RoleType = SystemPermissionRoleType.Writer },
                new() { Id = 2, SystemPermissionEnvironmentId = 1, OId = "user2", Name = "User 2", RoleType = SystemPermissionRoleType.Reader }
            })
            .AddEnvironment(2, SystemPermissionEnvironmentNames.Staging, new List<SystemPermissionRole>
            {
                new() { Id = 3, SystemPermissionEnvironmentId = 2, OId = "user3", Name = "User 3", RoleType = SystemPermissionRoleType.Writer }
            })
            .Build();

        // Set up mocks
        _systemPermissionStorageMock.GetByIdAsync(1).Returns(testSystemPermission);
        _systemPermissionStorageMock.UpdateAsync(Arg.Any<SystemPermission>()).Returns(testSystemPermission);
        _systemPermissionStorageMock.DeleteAsync(Arg.Any<SystemPermission>()).Returns(1);
        _clientStorageMock.AnyAsync(Arg.Any<Expression<Func<ClientExt, bool>>>()).Returns(false);
        _apiResourceStorageMock.AnyAsync(Arg.Any<Expression<Func<ApiResourceExt, bool>>>()).Returns(false);
        _permissionCheckerMock.GetAccessRoleOrThrowIfNoAccessToSystem(Arg.Any<ClaimsPrincipal>(), Arg.Any<SystemPermission>(), Arg.Any<EntityAccessType>(), Arg.Any<string>()).Returns(SystemPermissionRoleType.Writer);

        var timeBeforeDelete = DateTime.UtcNow;

        // Act
        var result = await _sut.DeleteAsync(_user, 1);

        // Assert
        await _systemPermissionStorageMock.Received(1).UpdateAsync(Arg.Is<SystemPermission>(entity =>
            entity.Updated.HasValue &&
            entity.Updated.Value >= timeBeforeDelete &&
            entity.Environments.All(env => env.Updated.HasValue && env.Updated.Value >= timeBeforeDelete) &&
            entity.Environments.SelectMany(env => env.Permissions).All(perm => perm.Updated.HasValue && perm.Updated.Value >= timeBeforeDelete)
        ));

        await _systemPermissionStorageMock.Received(1).DeleteAsync(testSystemPermission);

        Assert.That(result, Is.EqualTo(1));
    }
}
