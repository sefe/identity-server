// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

using System.Linq.Expressions;
using System.Security.Claims;
using AutoMapper;
using Duende.IdentityServer.EntityFramework.Entities;
using NSubstitute;
using IdentityServer.Abstraction.Contracts;
using IdentityServer.Abstraction.Entities.IdentityServerConfig;
using IdentityServer.Abstraction.Entities.IdentityServerConfig.SystemPermissions;
using IdentityServer.Data.DuendeEntityExtensions;
using IdentityServer.Data.Entities.Roles;
using IdentityServer.Data.Repositories.DtoRepositories.Client;
using IdentityServer.Tests.Common.Builders;

namespace IdentityServer.Data.Test.Repositories;

/// <summary>
/// Tests only for use cases not explicitly covered by the <seealso cref="ClientControllerTests"/>.
/// </summary>
[TestFixture]
public class ClientDtoRepositoryTests
{
    private IStorage<ClientExt> _clientStorageMock;
    private IStorage<ApiScopeExt> _apiScopeStorageMock;
    private IStorage<ApiResourceExt> _apiResourceStorageMock;
    private IStorage<ApiResourceRole> _apiResourceRoleStorageMock;
    private IMapper _mapperMock;
    private IPermissionChecker _permissionCheckerMock;
    private ICache<Client> _cache;
    private IClientAuditService _auditServiceMock;
    private ClientDtoRepository _sut;
    private ClaimsPrincipal _user;

    [SetUp]
    public void SetUp()
    {
        _clientStorageMock = Substitute.For<IStorage<ClientExt>>();
        _apiScopeStorageMock = Substitute.For<IStorage<ApiScopeExt>>();
        _apiResourceStorageMock = Substitute.For<IStorage<ApiResourceExt>>();
        _apiResourceRoleStorageMock = Substitute.For<IStorage<ApiResourceRole>>();
        _mapperMock = Substitute.For<IMapper>();
        _permissionCheckerMock = Substitute.For<IPermissionChecker>();
        _cache = Substitute.For<ICache<Client>>();
    _auditServiceMock = Substitute.For<IClientAuditService>();

        _sut = new ClientDtoRepository(
            _clientStorageMock,
            _apiScopeStorageMock,
            _mapperMock,
            _permissionCheckerMock,
            _apiResourceStorageMock,
            _apiResourceRoleStorageMock,
            _cache,
            _auditServiceMock);

        _user = new ClaimsPrincipal();
    }

    [Test]
    public async Task DeleteAsync_WithNestedEntities_UpdatesAuditFieldsRecursively()
    {
        // Arrange
        var testClient = new ClientExtBuilder("test-client", "Test Client")
            .WithId(1)
            .WithRole("TestRole", new List<ClientRoleMapping>
            {
                new() { Id = 1, ClientRoleId = 1, MappingType = ClientRoleMapType.UserObjectId, Value = "user1" }
            })
            .WithSecret("secret")
            .WithRedirectUri("https://test.com")
            .WithCorsOrigin("https://test.com")
            .WithGrantType(ClientGrantTypeNames.Grant_Code)
            .WithEntraApp("test-app-id", "Test App")
            .WithScope("test-scope")
            .Build();

        // Set up mocks
        _clientStorageMock.GetByIdAsync(1).Returns(testClient);
        _clientStorageMock.UpdateAsync(Arg.Any<ClientExt>()).Returns(testClient);
        _clientStorageMock.DeleteAsync(Arg.Any<ClientExt>()).Returns(1);
        _apiResourceRoleStorageMock.ToListAsync(Arg.Any<Expression<Func<ApiResourceRole, bool>>>()).Returns(new List<ApiResourceRole>());
        _permissionCheckerMock.GetAccessRoleOrThrowIfNoAccessToEnvAsync(Arg.Any<ClaimsPrincipal>(), Arg.Any<int>(), Arg.Any<EntityAccessType>(), Arg.Any<string>()).Returns(SystemPermissionRoleType.Writer);

        var timeBeforeDelete = DateTime.UtcNow;

        // Act
        var result = await _sut.DeleteAsync(_user, 1);

        // Assert
        await _clientStorageMock.Received(1).UpdateAsync(Arg.Is<ClientExt>(entity =>
            entity.Updated.HasValue &&
            entity.Updated.Value >= timeBeforeDelete &&
            entity.Roles.All(r => r.Updated.HasValue && r.Updated.Value >= timeBeforeDelete) &&
            entity.Roles.SelectMany(r => r.Mappings).All(m => m.Updated.HasValue && m.Updated.Value >= timeBeforeDelete) &&
            entity.ClientSecrets.OfType<ClientSecretExt>().All(s => s.Updated.HasValue && s.Updated.Value >= timeBeforeDelete) &&
            entity.AllowedScopes.OfType<ClientScopeExt>().All(sc => sc.Updated.HasValue && sc.Updated.Value >= timeBeforeDelete) &&
            entity.RedirectUris.OfType<ClientRedirectUriExt>().All(r => r.Updated.HasValue && r.Updated.Value >= timeBeforeDelete) &&
            entity.AllowedGrantTypes.OfType<ClientGrantTypeExt>().All(gt => gt.Updated.HasValue && gt.Updated.Value >= timeBeforeDelete) &&
            entity.AllowedCorsOrigins.OfType<ClientCorsOriginExt>().All(co => co.Updated.HasValue && co.Updated.Value >= timeBeforeDelete) &&
            entity.EntraApps.All(ea => ea.Updated.HasValue && ea.Updated.Value >= timeBeforeDelete)
        ));

        await _clientStorageMock.Received(1).DeleteAsync(testClient);

        Assert.That(result, Is.EqualTo(1));
    }
}
