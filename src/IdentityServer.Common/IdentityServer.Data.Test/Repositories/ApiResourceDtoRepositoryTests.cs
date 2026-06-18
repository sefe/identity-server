using System.Linq.Expressions;
using System.Security.Claims;
using AutoMapper;
using Duende.IdentityServer.EntityFramework.Entities;
using Microsoft.Extensions.Logging;
using NSubstitute;
using IdentityServer.Abstraction.Contracts;
using IdentityServer.Abstraction.Entities.IdentityServerConfig;
using IdentityServer.Abstraction.Entities.IdentityServerConfig.SystemPermissions;
using IdentityServer.Data.DuendeEntityExtensions;
using IdentityServer.Data.Entities.Roles;
using IdentityServer.Data.Repositories.DtoRepositories.ApiResource;
using IdentityServer.Tests.Common.Builders;

namespace IdentityServer.Data.Test.Repositories;

/// <summary>
/// Tests only for use cases not explicitly covered by the <seealso cref="ApiResourceControllerTests"/>.
/// </summary>
[TestFixture]
public class ApiResourceDtoRepositoryTests
{
    private IStorage<ApiResourceExt> _apiResourceStorageMock;
    private IStorage<ClientScopeExt> _clientScopeStorageMock;
    private IStorage<ApiScopeExt> _apiScopeStorageMock;
    private IMapper _mapperMock;
    private IPermissionChecker _permissionCheckerMock;
    private ILogger<ApiResourceDtoRepository> _loggerMock;
    private IApiResourceAuditService _auditServiceMock;
    private ApiResourceDtoRepository _sut;
    private ClaimsPrincipal _user;
    private ICache<ApiResource> _cache;

    [SetUp]
    public void SetUp()
    {
        _apiResourceStorageMock = Substitute.For<IStorage<ApiResourceExt>>();
        _clientScopeStorageMock = Substitute.For<IStorage<ClientScopeExt>>();
        _apiScopeStorageMock = Substitute.For<IStorage<ApiScopeExt>>();
        _mapperMock = Substitute.For<IMapper>();
        _permissionCheckerMock = Substitute.For<IPermissionChecker>();
        _loggerMock = Substitute.For<ILogger<ApiResourceDtoRepository>>();
        _cache = Substitute.For<ICache<ApiResource>>();
        _auditServiceMock = Substitute.For<IApiResourceAuditService>();

        _sut = new ApiResourceDtoRepository(
            _apiResourceStorageMock,
            _apiScopeStorageMock,
            _clientScopeStorageMock,
            _mapperMock,
            _permissionCheckerMock,
            _cache,
            _auditServiceMock,
            _loggerMock);

        _user = new ClaimsPrincipal();
    }

    [Test]
    public async Task DeleteAsync_WithNestedEntities_DeletesAssociatedApiScopesAndUpdatesAuditFieldsRecursively()
    {
        // Arrange
        var testApiResource = new ApiResourceExtBuilder("test-api")
            .WithId(1)
            .WithSecret("secret")
            .WithScope("test-api.read")
            .WithScope("test-api.write")
            .WithRole("TestRole", new List<RoleMapping>
            {
                new() { Id = 1, ApiResourceRoleId = 1, MappingType = RoleMapType.UserObjectId, Value = "user1" }
            })
            .Build();

        var associatedApiScope1 = new ApiScopeExt
        {
            Id = 1,
            Name = "test-api.read",
            Enabled = true
        };
        var associatedApiScope2 = new ApiScopeExt
        {
            Id = 2,
            Name = "test-api.write",
            Enabled = true
        };
        var apiScopesToDelete = new List<ApiScopeExt> { associatedApiScope1, associatedApiScope2 };

        // Set up mocks
        _apiResourceStorageMock.GetByIdAsync(1).Returns(testApiResource);
        _apiResourceStorageMock.UpdateAsync(Arg.Any<ApiResourceExt>()).Returns(testApiResource);
        _apiResourceStorageMock.DeleteAsync(Arg.Any<ApiResourceExt>()).Returns(1);
        _clientScopeStorageMock.ToListAsync(Arg.Any<Expression<Func<ClientScopeExt, bool>>>()).Returns(new List<ClientScopeExt>());
        _apiScopeStorageMock.ToListAsync(Arg.Any<Expression<Func<ApiScopeExt, bool>>>()).Returns(apiScopesToDelete);
        _apiScopeStorageMock.UpdateAsync(Arg.Any<ApiScopeExt>()).Returns((callInfo) => callInfo.Arg<ApiScopeExt>());
        _apiScopeStorageMock.DeleteAsync(Arg.Any<IEnumerable<ApiScopeExt>>()).Returns(Task.CompletedTask);
        _permissionCheckerMock.GetAccessRoleOrThrowIfNoAccessToEnvAsync(Arg.Any<ClaimsPrincipal>(), Arg.Any<int>(), Arg.Any<EntityAccessType>(), Arg.Any<string>()).Returns(SystemPermissionRoleType.Writer);

        var timeBeforeDelete = DateTime.UtcNow;

        // Act
        var result = await _sut.DeleteAsync(_user, 1);

        // Assert - Verify main entity audit fields are updated recursively
        await _apiResourceStorageMock.Received(1).UpdateAsync(Arg.Is<ApiResourceExt>(entity =>
            entity.Updated.HasValue &&
            entity.Updated.Value >= timeBeforeDelete &&
            entity.Roles.All(r => r.Updated.HasValue && r.Updated.Value >= timeBeforeDelete) &&
            entity.Roles.SelectMany(r => r.Mappings).All(m => m.Updated.HasValue && m.Updated.Value >= timeBeforeDelete) &&
            entity.Secrets.OfType<ApiResourceSecretExt>().All(s => s.Updated.HasValue && s.Updated.Value >= timeBeforeDelete) &&
            entity.Scopes.OfType<ApiResourceScopeExt>().All(sc => sc.Updated.HasValue && sc.Updated.Value >= timeBeforeDelete)
        ));

        // Verify associated ApiScope entities are updated and deleted
        await _apiScopeStorageMock.Received(2).UpdateAsync(Arg.Is<ApiScopeExt>(scope =>
            scope.Updated.HasValue && scope.Updated.Value >= timeBeforeDelete));
        await _apiScopeStorageMock.Received(1).DeleteAsync(apiScopesToDelete);

        // Verify main entity operations
        await _apiResourceStorageMock.Received(1).DeleteAsync(testApiResource);
        Assert.That(result, Is.EqualTo(1));
    }
}
