// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

using System.Security.Claims;
using AutoMapper;
using NSubstitute;
using IdentityServer.Abstraction.Contracts;
using IdentityServer.Abstraction.Entities.IdentityServerConfig;
using IdentityServer.Abstraction.Entities.IdentityServerConfig.SystemPermissions;
using IdentityServer.Data.DuendeEntityExtensions;
using IdentityServer.Data.Entities.Roles;
using IdentityServer.Data.Repositories.DtoRepositories.Client;
using IdentityServer.Data.Repositories.Storage;
using IdentityServer.Tests.Common.Builders;

namespace IdentityServer.Data.Test.Repositories;

/// <summary>
/// Tests for ClientPropertyRoleDtoRepository focusing on audit timestamp behavior during deletion.
/// </summary>
[TestFixture]
public class ClientPropertyRoleDtoRepositoryTests
{
    private IStorage<ClientExt> _clientStorageMock;
    private IStorage<ClientRole> _roleStorageMock;
    private IMapper _mapperMock;
    private IPermissionChecker _permissionCheckerMock;
    private IParentAccessor<ClientRole, ClientExt> _parentAccessorMock;
    private ClientPropertyRoleDtoRepository _sut;
    private ClaimsPrincipal _user;

    [SetUp]
    public void SetUp()
    {
        _clientStorageMock = Substitute.For<IStorage<ClientExt>>();
        _roleStorageMock = Substitute.For<IStorage<ClientRole>>();
        _mapperMock = Substitute.For<IMapper>();
        _permissionCheckerMock = Substitute.For<IPermissionChecker>();
        _parentAccessorMock = Substitute.For<IParentAccessor<ClientRole, ClientExt>>();

        _sut = new ClientPropertyRoleDtoRepository(
            _clientStorageMock,
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
        var clientId = 1;
        var roleId = 10;
        var mappings = new List<ClientRoleMapping>
        {
            new() { Id = 1, ClientRoleId = roleId, MappingType = ClientRoleMapType.SecurityGroup, Value = "group1" },
            new() { Id = 2, ClientRoleId = roleId, MappingType = ClientRoleMapType.UserObjectId, Value = "user1" }
        };
        
        var testClient = new ClientExtBuilder("test-client", "Test Client")
            .WithId(clientId)
            .WithRole("TestRole", mappings)
            .Build();
        
        var testRole = testClient.Roles.First();
        testRole.Id = roleId;
        testRole.ClientId = clientId;

        _roleStorageMock.GetByIdAsync(roleId).Returns(testRole);
        _parentAccessorMock.GetParentId(testRole).Returns(clientId);
        _clientStorageMock.GetByIdAsync(clientId).Returns(testClient);
        _parentAccessorMock.GetParentEnvironmentId(testClient).Returns(1);
        _permissionCheckerMock.GetAccessRoleOrThrowIfNoAccessToEnvAsync(Arg.Any<ClaimsPrincipal>(), Arg.Any<int>(), Arg.Any<EntityAccessType>(), Arg.Any<string>())
            .Returns(SystemPermissionRoleType.Writer);
        _roleStorageMock.UpdateAsync(Arg.Any<ClientRole>()).Returns(testRole);
        _roleStorageMock.DeleteAsync(Arg.Any<ClientRole>()).Returns(1);

        var timeBeforeDelete = DateTime.UtcNow;

        // Act
        var result = await _sut.DeleteAsync(_user, roleId);

        // Assert
        await _roleStorageMock.Received(2).UpdateAsync(Arg.Is<ClientRole>(role =>
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
        var clientId = 1;
        var roleId = 10;
        
        var testClient = new ClientExtBuilder("test-client", "Test Client")
            .WithId(clientId)
            .WithRole("TestRole", new List<ClientRoleMapping>())
            .Build();
        
        var testRole = testClient.Roles.First();
        testRole.Id = roleId;
        testRole.ClientId = clientId;

        _roleStorageMock.GetByIdAsync(roleId).Returns(testRole);
        _parentAccessorMock.GetParentId(testRole).Returns(clientId);
        _clientStorageMock.GetByIdAsync(clientId).Returns(testClient);
        _parentAccessorMock.GetParentEnvironmentId(testClient).Returns(1);
        _permissionCheckerMock.GetAccessRoleOrThrowIfNoAccessToEnvAsync(Arg.Any<ClaimsPrincipal>(), Arg.Any<int>(), Arg.Any<EntityAccessType>(), Arg.Any<string>())
            .Returns(SystemPermissionRoleType.Writer);
        _roleStorageMock.UpdateAsync(Arg.Any<ClientRole>()).Returns(testRole);
        _roleStorageMock.DeleteAsync(Arg.Any<ClientRole>()).Returns(1);

        var timeBeforeDelete = DateTime.UtcNow;

        // Act
        var result = await _sut.DeleteAsync(_user, roleId);

        // Assert
        await _roleStorageMock.Received(2).UpdateAsync(Arg.Is<ClientRole>(role =>
            role.Updated.HasValue &&
            role.Updated.Value >= timeBeforeDelete
        ));

        await _roleStorageMock.Received(1).DeleteAsync(testRole);
    }
}
