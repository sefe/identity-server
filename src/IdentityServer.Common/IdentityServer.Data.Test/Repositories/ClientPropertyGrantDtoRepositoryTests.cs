// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

using AutoMapper;
using Duende.IdentityServer.EntityFramework.Entities;
using NSubstitute;
using System.Security.Claims;
using IdentityServer.Abstraction.Contracts;
using IdentityServer.Abstraction.DTO.Clients;
using IdentityServer.Abstraction.Entities.IdentityServerConfig;
using IdentityServer.Abstraction.Exceptions;
using IdentityServer.Data.DuendeEntityExtensions;
using IdentityServer.Data.Repositories.DtoRepositories.Client;
using IdentityServer.Data.Repositories.Storage;
using IdentityServer.Tests.Common.Builders;

namespace IdentityServer.Data.Test.Repositories;

[TestFixture]
public class ClientPropertyGrantDtoRepositoryTests
{
    private IStorage<ClientExt> _clientStorage;
    private IStorage<ClientGrantTypeExt> _propertyStorage;
    private IMapper _mapper;
    private IPermissionChecker _permissionChecker;
    private IParentAccessor<ClientGrantTypeExt, ClientExt> _parentAccessor;
    private ClientPropertyGrantDtoRepository _sut;
    private ClaimsPrincipal _user;
    private ClientExt _client;
    private ICache<Client> _cache;

    private const int _clientId = 99;

    [SetUp]
    public void SetUp()
    {
        _clientStorage = Substitute.For<IStorage<ClientExt>>();
        _propertyStorage = Substitute.For<IStorage<ClientGrantTypeExt>>();
        _mapper = Substitute.For<IMapper>();
        _permissionChecker = Substitute.For<IPermissionChecker>();
        _parentAccessor = Substitute.For<IParentAccessor<ClientGrantTypeExt, ClientExt>>();
        _cache = Substitute.For<ICache<Client>>();
        _sut = new ClientPropertyGrantDtoRepository(
            _clientStorage,
            _propertyStorage,
            _mapper,
            _permissionChecker,
            _parentAccessor,
            _cache
        );
        _user = new ClaimsPrincipal();
        _client = new ClientExtBuilder("test-client", "Test Client")
            .WithId(_clientId)
            .Build();
    }

    [Test]
    public async Task CreateAsync_WithImplicitGrantType_UpdatesAllowAccessTokensViaBrowser()
    {
        // Arrange
        _client.AllowedGrantTypes = new List<ClientGrantType>();
        var createDto = new ClientPropertyGrantDtoCreate
        {
            ClientId = _clientId,
            GrantType = ClientGrantTypeNames.Grant_Implicit
        };
        var propertyToCreate = new ClientGrantTypeExt
        {
            ClientId = _clientId,
            GrantType = ClientGrantTypeNames.Grant_Implicit
        };
        var createdProperty = new ClientPropertyGrantDtoRead
        {
            ClientId = _clientId,
            GrantType = ClientGrantTypeNames.Grant_Implicit
        };

        _clientStorage.GetByIdAsync(_clientId).Returns(_client);
        _propertyStorage.FirstOrDefaultAsync(Arg.Any<System.Linq.Expressions.Expression<Func<ClientGrantTypeExt, bool>>>())
            .Returns((ClientGrantTypeExt)null);
        _mapper.Map<ClientGrantTypeExt>(createDto).Returns(propertyToCreate);
        _propertyStorage.AddAsync(propertyToCreate).Returns(propertyToCreate);
        _mapper.Map<ClientPropertyGrantDtoRead>(propertyToCreate).Returns(createdProperty);
        _clientStorage.UpdateAsync(_client).Returns(_client);

        // Act
        await _sut.CreateAsync(_user, createDto);

        // Assert
        Assert.That(_client.AllowAccessTokensViaBrowser, Is.True);
        await _clientStorage.Received(1).UpdateAsync(_client);
    }

    [Test]
    public async Task DeleteAsync_WithImplicitGrantType_UpdatesAllowAccessTokensViaBrowserToFalse()
    {
        // Arrange
        _client.AllowAccessTokensViaBrowser = true;
        _client.AllowedGrantTypes = new List<ClientGrantType>
        {
            new() { Id = 1, GrantType = ClientGrantTypeNames.Grant_Implicit },
            new() { Id = 2, GrantType = ClientGrantTypeNames.Grant_ClientCredentials }
        };
        var propertyToDelete = new ClientGrantTypeExt
        {
            Id = 1,
            ClientId = _clientId,
            GrantType = ClientGrantTypeNames.Grant_Implicit
        };
        var deleteDto = new ClientPropertyGrantDtoRead
        {
            Id = 1,
            ClientId = _clientId,
            GrantType = ClientGrantTypeNames.Grant_Implicit
        };

        _clientStorage.GetByIdAsync(_clientId).Returns(_client);
        _parentAccessor.GetParentId(propertyToDelete).Returns(_clientId);
        _propertyStorage.GetByIdAsync(propertyToDelete.Id).Returns(propertyToDelete);
        _mapper.Map<ClientGrantTypeExt>(deleteDto).Returns(propertyToDelete);
        _propertyStorage.DeleteAsync(propertyToDelete).Returns(1);
        _clientStorage.UpdateAsync(_client).Returns(_client);

        // Act
        await _sut.DeleteAsync(_user, deleteDto.Id);

        // Assert
        Assert.That(_client.AllowAccessTokensViaBrowser, Is.False);
        await _clientStorage.Received(1).UpdateAsync(_client);
    }

    [Test]
    public void DeleteAsync_WithLastGrant_ThrowsException()
    {
        // Arrange
        _client.AllowAccessTokensViaBrowser = true;
        _client.AllowedGrantTypes = new List<ClientGrantType>
        {
            new() { Id = 1, GrantType = ClientGrantTypeNames.Grant_Implicit }
        };
        var propertyToDelete = new ClientGrantTypeExt
        {
            Id = 1,
            ClientId = _clientId,
            GrantType = ClientGrantTypeNames.Grant_Implicit
        };
        var deleteDto = new ClientPropertyGrantDtoRead
        {
            Id = 1,
            ClientId = _clientId,
            GrantType = ClientGrantTypeNames.Grant_Implicit
        };

        _clientStorage.GetByIdAsync(_clientId).Returns(_client);
        _parentAccessor.GetParentId(propertyToDelete).Returns(_clientId);
        _propertyStorage.GetByIdAsync(propertyToDelete.Id).Returns(propertyToDelete);
        _mapper.Map<ClientGrantTypeExt>(deleteDto).Returns(propertyToDelete);
        _propertyStorage.DeleteAsync(propertyToDelete).Returns(1);
        _clientStorage.UpdateAsync(_client).Returns(_client);

        // Act & Assert
        Assert.ThrowsAsync<EntityReferenceException>(async () => await _sut.DeleteAsync(_user, deleteDto.Id));
    }
}
