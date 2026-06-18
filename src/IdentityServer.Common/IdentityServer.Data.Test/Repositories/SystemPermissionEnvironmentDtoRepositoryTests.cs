using System.Linq.Expressions;
using System.Security.Claims;
using AutoMapper;
using NSubstitute;
using IdentityServer.Abstraction.Contracts;
using IdentityServer.Abstraction.Entities.IdentityServerConfig.SystemPermissions;
using IdentityServer.Data.DuendeEntityExtensions;
using IdentityServer.Data.Repositories.DtoRepositories;

namespace IdentityServer.Data.Test.Repositories;

/// <summary>
/// Tests only for use cases not explicitly covered by the <seealso cref="SystemPermissionEnvironmentControllerTests"/>.
/// </summary>
[TestFixture]
public class SystemPermissionEnvironmentDtoRepositoryTests
{
    private IStorage<SystemPermission> _systemPermissionStorageMock;
    private IStorage<SystemPermissionEnvironment> _environmentStorageMock;
    private IStorage<SystemPermissionRole> _roleStorageMock;
    private IStorage<ClientExt> _clientStorageMock;
    private IStorage<ApiResourceExt> _apiResourceStorageMock;
    private IMapper _mapperMock;
    private IPermissionChecker _permissionCheckerMock;
    private SystemPermissionEnvironmentDtoRepository _sut;
    private ClaimsPrincipal _user;

    [SetUp]
    public void SetUp()
    {
        _systemPermissionStorageMock = Substitute.For<IStorage<SystemPermission>>();
        _environmentStorageMock = Substitute.For<IStorage<SystemPermissionEnvironment>>();
        _roleStorageMock = Substitute.For<IStorage<SystemPermissionRole>>();
        _clientStorageMock = Substitute.For<IStorage<ClientExt>>();
        _apiResourceStorageMock = Substitute.For<IStorage<ApiResourceExt>>();
        _mapperMock = Substitute.For<IMapper>();
        _permissionCheckerMock = Substitute.For<IPermissionChecker>();

        _sut = new SystemPermissionEnvironmentDtoRepository(
            _systemPermissionStorageMock,
            _environmentStorageMock,
            _roleStorageMock,
            _clientStorageMock,
            _apiResourceStorageMock,
            _mapperMock,
            _permissionCheckerMock);

        _user = new ClaimsPrincipal();
    }

    [Test]
    public async Task DeleteAsync_WithNestedPermissions_UpdatesAuditFieldsRecursively()
    {
        // Arrange
        var testEnvironment = new SystemPermissionEnvironment
        {
            Id = 1,
            Environment = SystemPermissionEnvironmentNames.Development,
            SystemPermissionId = 1,
            SystemPermission = new SystemPermission { Id = 1, Name = "Test System Permission", Description = "Test Description" },
            Permissions = new List<SystemPermissionRole>
            {
                new() { Id = 1, SystemPermissionEnvironmentId = 1, OId = "user1", Name = "User 1", RoleType = SystemPermissionRoleType.Writer },
                new() { Id = 2, SystemPermissionEnvironmentId = 1, OId = "user2", Name = "User 2", RoleType = SystemPermissionRoleType.Reader }
            }
        };

        _environmentStorageMock.GetByIdAsync(1).Returns(testEnvironment);
        _environmentStorageMock.UpdateAsync(Arg.Any<SystemPermissionEnvironment>()).Returns(testEnvironment);
        _environmentStorageMock.DeleteAsync(Arg.Any<SystemPermissionEnvironment>()).Returns(1);
        _clientStorageMock.AnyAsync(Arg.Any<Expression<Func<ClientExt, bool>>>()).Returns(false);
        _apiResourceStorageMock.AnyAsync(Arg.Any<Expression<Func<ApiResourceExt, bool>>>()).Returns(false);
        _permissionCheckerMock.GetAccessRoleOrThrowIfNoAccessToEnvAsync(Arg.Any<ClaimsPrincipal>(), Arg.Any<int>(), Arg.Any<EntityAccessType>(), Arg.Any<string>()).Returns(SystemPermissionRoleType.Writer);

        var timeBeforeDelete = DateTime.UtcNow;

        // Act
        var result = await _sut.DeleteAsync(_user, 1);

        // Assert
        await _environmentStorageMock.Received(1).UpdateAsync(Arg.Is<SystemPermissionEnvironment>(entity =>
            entity.Updated.HasValue &&
            entity.Updated.Value >= timeBeforeDelete &&
            entity.Permissions.All(perm => perm.Updated.HasValue && perm.Updated.Value >= timeBeforeDelete)
        ));

        await _environmentStorageMock.Received(1).DeleteAsync(testEnvironment);

        Assert.That(result, Is.EqualTo(1));
    }
}
