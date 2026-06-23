// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

using System.Security.Claims;
using AutoMapper;
using NSubstitute;
using IdentityServer.Abstraction.Contracts;
using IdentityServer.Abstraction.Entities.IdentityServerConfig.SystemPermissions;
using IdentityServer.Data.DuendeEntityExtensions;
using IdentityServer.Data.Entities.Roles;
using IdentityServer.Data.Repositories.DtoRepositories.ApiResource;
using IdentityServer.Data.Repositories.Storage;
using IdentityServer.Tests.Common.Builders;

namespace IdentityServer.Data.Test.Repositories;

/// <summary>
/// Tests for ApiResourcePropertyRoleDtoRepository focusing on audit timestamp behavior during deletion.
/// </summary>
[TestFixture]
public class ApiResourcePropertyRoleDtoRepositoryTests
{
    private IStorage<ApiResourceExt> _apiResourceStorageMock;
    private IStorage<ApiResourceRole> _roleStorageMock;
    private IMapper _mapperMock;
    private IPermissionChecker _permissionCheckerMock;
    private IParentAccessor<ApiResourceRole, ApiResourceExt> _parentAccessorMock;
    private ApiResourcePropertyRoleDtoRepository _sut;
    private ClaimsPrincipal _user;

    [SetUp]
    public void SetUp()
    {
        _apiResourceStorageMock = Substitute.For<IStorage<ApiResourceExt>>();
        _roleStorageMock = Substitute.For<IStorage<ApiResourceRole>>();
        _mapperMock = Substitute.For<IMapper>();
        _permissionCheckerMock = Substitute.For<IPermissionChecker>();
        _parentAccessorMock = Substitute.For<IParentAccessor<ApiResourceRole, ApiResourceExt>>();

        _sut = new ApiResourcePropertyRoleDtoRepository(
            _apiResourceStorageMock,
            _roleStorageMock,
            _mapperMock,
            _permissionCheckerMock,
            _parentAccessorMock);

        _user = new ClaimsPrincipal();
    }

    [Test]
    public async Task DeleteAsync_WithNestedMappings_UpdatesAuditFieldsRecursively()
    {
        // Arrange
        var apiResourceId = 1;
        var roleId = 10;
        var mappings = new List<RoleMapping>
        {
            new() { Id = 1, ApiResourceRoleId = roleId, Value = "group1" },
            new() { Id = 2, ApiResourceRoleId = roleId, Value = "group2" }
        };
        
        var testApiResource = new ApiResourceExtBuilder("test-api")
            .WithId(apiResourceId)
            .WithRole("TestRole", mappings)
            .Build();
        
        var testRole = testApiResource.Roles.First();
        testRole.Id = roleId;
        testRole.ApiResourceId = apiResourceId;

        _roleStorageMock.GetByIdAsync(roleId).Returns(testRole);
        _parentAccessorMock.GetParentId(testRole).Returns(apiResourceId);
        _apiResourceStorageMock.GetByIdAsync(apiResourceId).Returns(testApiResource);
        _parentAccessorMock.GetParentEnvironmentId(testApiResource).Returns(1);
        _permissionCheckerMock.GetAccessRoleOrThrowIfNoAccessToEnvAsync(Arg.Any<ClaimsPrincipal>(), Arg.Any<int>(), Arg.Any<EntityAccessType>(), Arg.Any<string>())
            .Returns(SystemPermissionRoleType.Writer);
        _roleStorageMock.UpdateAsync(Arg.Any<ApiResourceRole>()).Returns(testRole);
        _roleStorageMock.DeleteAsync(Arg.Any<ApiResourceRole>()).Returns(1);

        var timeBeforeDelete = DateTime.UtcNow;

        // Act
        var result = await _sut.DeleteAsync(_user, roleId);

        // Assert
        await _roleStorageMock.Received(2).UpdateAsync(Arg.Is<ApiResourceRole>(role =>
            role.Updated.HasValue &&
            role.Updated.Value >= timeBeforeDelete &&
            role.Mappings.All(mapping => mapping.Updated.HasValue && mapping.Updated.Value >= timeBeforeDelete)
        ));

        await _roleStorageMock.Received(1).DeleteAsync(testRole);
    }

    [Test]
    public async Task DeleteAsync_WithoutMappings_StillUpdatesRoleAuditFields()
    {
        // Arrange
        var apiResourceId = 1;
        var roleId = 10;
        
        var testApiResource = new ApiResourceExtBuilder("test-api")
            .WithId(apiResourceId)
            .WithRole("TestRole", new List<RoleMapping>())
            .Build();
        
        var testRole = testApiResource.Roles.First();
        testRole.Id = roleId;
        testRole.ApiResourceId = apiResourceId;

        _roleStorageMock.GetByIdAsync(roleId).Returns(testRole);
        _parentAccessorMock.GetParentId(testRole).Returns(apiResourceId);
        _apiResourceStorageMock.GetByIdAsync(apiResourceId).Returns(testApiResource);
        _parentAccessorMock.GetParentEnvironmentId(testApiResource).Returns(1);
        _permissionCheckerMock.GetAccessRoleOrThrowIfNoAccessToEnvAsync(Arg.Any<ClaimsPrincipal>(), Arg.Any<int>(), Arg.Any<EntityAccessType>(), Arg.Any<string>())
            .Returns(SystemPermissionRoleType.Writer);
        _roleStorageMock.UpdateAsync(Arg.Any<ApiResourceRole>()).Returns(testRole);
        _roleStorageMock.DeleteAsync(Arg.Any<ApiResourceRole>()).Returns(1);

        var timeBeforeDelete = DateTime.UtcNow;

        // Act
        var result = await _sut.DeleteAsync(_user, roleId);

        // Assert
        await _roleStorageMock.Received(2).UpdateAsync(Arg.Is<ApiResourceRole>(role =>
            role.Updated.HasValue &&
            role.Updated.Value >= timeBeforeDelete
        ));

        await _roleStorageMock.Received(1).DeleteAsync(testRole);
    }
}
