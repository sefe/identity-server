// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

using System.Security.Claims;
using AutoMapper;
using Duende.IdentityServer.EntityFramework.Entities;
using Duende.IdentityServer.Models;
using Microsoft.Extensions.Options;
using NSubstitute;
using IdentityServer.Abstraction.Configs;
using IdentityServer.Abstraction.Contracts;
using IdentityServer.Abstraction.DTO.Clients;
using IdentityServer.Abstraction.Exceptions;
using IdentityServer.Data.DuendeEntityExtensions;
using IdentityServer.Data.Repositories.DtoRepositories.Client;
using IdentityServer.Data.Repositories.Storage;
using IdentityServer.Tests.Common.Builders;

namespace IdentityServer.Data.Test.Repositories;

[TestFixture]
public class ClientPropertySecretDtoRepositoryTests
{
    private IStorage<ClientExt> _clientStorage;
    private IStorage<ClientSecretExt> _propertyStorage;
    private IMapper _mapper;
    private IPermissionChecker _permissionChecker;
    private ISecretGeneratorService _secretGenerator;
    private IParentAccessor<ClientSecretExt, ClientExt> _parentAccessor;
    private ICache<Duende.IdentityServer.EntityFramework.Entities.Client> _clientCache;
    private IOptions<SecretExpirationConfig> _expirationConfig;
    private ClientPropertySecretDtoRepository _sut;
    private ClaimsPrincipal _user;

    [SetUp]
    public void SetUp()
    {
        _clientStorage = Substitute.For<IStorage<ClientExt>>();
        _propertyStorage = Substitute.For<IStorage<ClientSecretExt>>();
        _mapper = Substitute.For<IMapper>();
        _permissionChecker = Substitute.For<IPermissionChecker>();
        _secretGenerator = Substitute.For<ISecretGeneratorService>();
        _parentAccessor = Substitute.For<IParentAccessor<ClientSecretExt, ClientExt>>();
        _clientCache = Substitute.For<ICache<Duende.IdentityServer.EntityFramework.Entities.Client>>();
        _expirationConfig = Options.Create(new SecretExpirationConfig { MaxValidityYears = 2 });

        _sut = new ClientPropertySecretDtoRepository(
            _clientStorage,
            _propertyStorage,
            _mapper,
            _permissionChecker,
            _secretGenerator,
            _parentAccessor,
            _clientCache,
            _expirationConfig);

        _user = new ClaimsPrincipal();
    }

    [Test]
    public async Task CreateAsync_WithValidityPeriodExceedingMaximum_ThrowsEntityValidationException()
    {
        // Arrange
        var clientId = 1;
        var createDto = new ClientPropertySecretDtoCreate
        {
            ClientId = clientId,
            Description = "Test Secret",
            ValidityPeriodYears = 3 // Exceeds configured maximum of 2
        };

        var client = new ClientExtBuilder("test-client", "Test Client")
            .WithId(clientId)
            .Build();

        _propertyStorage.FirstOrDefaultAsync(Arg.Any<System.Linq.Expressions.Expression<Func<ClientSecretExt, bool>>>())
            .Returns((ClientSecretExt)null);

        _clientStorage.GetByIdAsync(clientId).Returns(client);
        _permissionChecker.GetAccessRoleOrThrowIfNoAccessToEnvAsync(
            Arg.Any<ClaimsPrincipal>(),
            Arg.Any<int>(),
            Arg.Any<EntityAccessType>(),
            Arg.Any<string>()).Returns(Abstraction.Entities.IdentityServerConfig.SystemPermissions.SystemPermissionRoleType.Writer);

        // Act & Assert
        var ex = Assert.ThrowsAsync<EntityValidationException>(async () => await _sut.CreateAsync(_user, createDto));
        Assert.That(ex.Message, Does.Contain("Validity period cannot exceed 2 years"));
    }

    [Test]
    public async Task CreateAsync_WithValidityPeriodEqualToMaximum_DoesNotThrow()
    {
        // Arrange
        var clientId = 1;
        var createDto = new ClientPropertySecretDtoCreate
        {
            ClientId = clientId,
            Description = "Test Secret",
            ValidityPeriodYears = 2 // Equal to configured maximum
        };

        var client = new ClientExtBuilder("test-client", "Test Client")
            .WithId(clientId)
            .Build();

        var secretValue = "generated-secret-value";
        var expectedExpiration = DateTime.UtcNow.AddYears(2);
        var createdSecret = new ClientSecretExt
        {
            ClientId = clientId,
            Description = "Test Secret",
            Value = secretValue.Sha256(),
            Preview = secretValue.Substring(0, 4),
            Expiration = expectedExpiration
        };

        _propertyStorage.FirstOrDefaultAsync(Arg.Any<System.Linq.Expressions.Expression<Func<ClientSecretExt, bool>>>())
            .Returns((ClientSecretExt)null);

        _clientStorage.GetByIdAsync(clientId).Returns(client);
        _permissionChecker.GetAccessRoleOrThrowIfNoAccessToEnvAsync(
            Arg.Any<ClaimsPrincipal>(),
            Arg.Any<int>(),
            Arg.Any<EntityAccessType>(),
            Arg.Any<string>()).Returns(Abstraction.Entities.IdentityServerConfig.SystemPermissions.SystemPermissionRoleType.Writer);

        _secretGenerator.GenerateSecureSecret().Returns(secretValue);
        _mapper.Map<ClientSecretExt>(createDto).Returns(new ClientSecretExt { ClientId = clientId, Description = "Test Secret" });
        _propertyStorage.AddAsync(Arg.Any<ClientSecretExt>()).Returns(createdSecret);
        _mapper.Map<ClientPropertySecretValueDtoRead>(createdSecret).Returns(new ClientPropertySecretValueDtoRead
        {
            ClientId = clientId,
            Description = "Test Secret",
            Expiration = expectedExpiration
        });

        // Act
        var result = await _sut.CreateAsync(_user, createDto);

        // Assert
        Assert.That(result, Is.Not.Null);
        await _propertyStorage.Received(1).AddAsync(Arg.Is<ClientSecretExt>(s => 
            s.Expiration.HasValue && 
            s.Expiration.Value >= expectedExpiration.AddSeconds(-5) && 
            s.Expiration.Value <= expectedExpiration.AddSeconds(5)));
    }

    [Test]
    public async Task CreateAsync_WithValidityPeriodBelowMaximum_DoesNotThrow()
    {
        // Arrange
        var clientId = 1;
        var createDto = new ClientPropertySecretDtoCreate
        {
            ClientId = clientId,
            Description = "Test Secret",
            ValidityPeriodYears = 1 // Below configured maximum
        };

        var client = new ClientExtBuilder("test-client", "Test Client")
            .WithId(clientId)
            .Build();

        var secretValue = "generated-secret-value";
        var expectedExpiration = DateTime.UtcNow.AddYears(1);
        var createdSecret = new ClientSecretExt
        {
            ClientId = clientId,
            Description = "Test Secret",
            Value = secretValue.Sha256(),
            Preview = secretValue.Substring(0, 4),
            Expiration = expectedExpiration
        };

        _propertyStorage.FirstOrDefaultAsync(Arg.Any<System.Linq.Expressions.Expression<Func<ClientSecretExt, bool>>>())
            .Returns((ClientSecretExt)null);

        _clientStorage.GetByIdAsync(clientId).Returns(client);
        _permissionChecker.GetAccessRoleOrThrowIfNoAccessToEnvAsync(
            Arg.Any<ClaimsPrincipal>(),
            Arg.Any<int>(),
            Arg.Any<EntityAccessType>(),
            Arg.Any<string>()).Returns(Abstraction.Entities.IdentityServerConfig.SystemPermissions.SystemPermissionRoleType.Writer);

        _secretGenerator.GenerateSecureSecret().Returns(secretValue);
        _mapper.Map<ClientSecretExt>(createDto).Returns(new ClientSecretExt { ClientId = clientId, Description = "Test Secret" });
        _propertyStorage.AddAsync(Arg.Any<ClientSecretExt>()).Returns(createdSecret);
        _mapper.Map<ClientPropertySecretValueDtoRead>(createdSecret).Returns(new ClientPropertySecretValueDtoRead
        {
            ClientId = clientId,
            Description = "Test Secret",
            Expiration = expectedExpiration
        });

        // Act
        var result = await _sut.CreateAsync(_user, createDto);

        // Assert
        Assert.That(result, Is.Not.Null);
        await _propertyStorage.Received(1).AddAsync(Arg.Is<ClientSecretExt>(s => 
            s.Expiration.HasValue && 
            s.Expiration.Value >= expectedExpiration.AddSeconds(-5) && 
            s.Expiration.Value <= expectedExpiration.AddSeconds(5)));
    }

    [Test]
    public async Task CreateAsync_SetsExpirationDateCorrectly()
    {
        // Arrange
        var clientId = 1;
        var validityYears = 2;
        var createDto = new ClientPropertySecretDtoCreate
        {
            ClientId = clientId,
            Description = "Test Secret",
            ValidityPeriodYears = validityYears
        };

        var client = new ClientExtBuilder("test-client", "Test Client")
            .WithId(clientId)
            .Build();

        var secretValue = "generated-secret-value";
        var timeBeforeCreate = DateTime.UtcNow;

        _propertyStorage.FirstOrDefaultAsync(Arg.Any<System.Linq.Expressions.Expression<Func<ClientSecretExt, bool>>>())
            .Returns((ClientSecretExt)null);

        _clientStorage.GetByIdAsync(clientId).Returns(client);
        _permissionChecker.GetAccessRoleOrThrowIfNoAccessToEnvAsync(
            Arg.Any<ClaimsPrincipal>(),
            Arg.Any<int>(),
            Arg.Any<EntityAccessType>(),
            Arg.Any<string>()).Returns(Abstraction.Entities.IdentityServerConfig.SystemPermissions.SystemPermissionRoleType.Writer);

        _secretGenerator.GenerateSecureSecret().Returns(secretValue);
        _mapper.Map<ClientSecretExt>(createDto).Returns(new ClientSecretExt { ClientId = clientId, Description = "Test Secret" });

        ClientSecretExt capturedSecret = null;
        _propertyStorage.AddAsync(Arg.Do<ClientSecretExt>(s => capturedSecret = s))
            .Returns(callInfo => callInfo.Arg<ClientSecretExt>());
        
        _mapper.Map<ClientPropertySecretValueDtoRead>(Arg.Any<ClientSecretExt>())
            .Returns(callInfo => new ClientPropertySecretValueDtoRead
            {
                ClientId = clientId,
                Description = "Test Secret",
                Expiration = callInfo.Arg<ClientSecretExt>().Expiration
            });

        // Act
        var result = await _sut.CreateAsync(_user, createDto);

        // Assert
        var timeAfterCreate = DateTime.UtcNow;
        var expectedExpiration = timeBeforeCreate.AddYears(validityYears);
        var maxExpectedExpiration = timeAfterCreate.AddYears(validityYears);

        using (Assert.EnterMultipleScope())
        {
            Assert.That(capturedSecret, Is.Not.Null);
            Assert.That(capturedSecret.Expiration, Is.Not.Null);
            Assert.That(capturedSecret.Expiration.Value, Is.GreaterThanOrEqualTo(expectedExpiration));
            Assert.That(capturedSecret.Expiration.Value, Is.LessThanOrEqualTo(maxExpectedExpiration));
        }
    }

    [Test]
    public async Task CreateAsync_WithDuplicateDescription_ThrowsEntityAlreadyExistsException()
    {
        // Arrange
        var clientId = 1;
        var description = "Duplicate Secret";
        var createDto = new ClientPropertySecretDtoCreate
        {
            ClientId = clientId,
            Description = description,
            ValidityPeriodYears = 2
        };

        var existingSecret = new ClientSecretExt
        {
            ClientId = clientId,
            Description = description
        };

        _propertyStorage.FirstOrDefaultAsync(Arg.Any<System.Linq.Expressions.Expression<Func<ClientSecretExt, bool>>>())
            .Returns(existingSecret);

        var client = new ClientExtBuilder("test-client", "Test Client")
            .WithId(clientId)
            .Build();

        _clientStorage.GetByIdAsync(clientId).Returns(client);
        _permissionChecker.GetAccessRoleOrThrowIfNoAccessToEnvAsync(
            Arg.Any<ClaimsPrincipal>(),
            Arg.Any<int>(),
            Arg.Any<EntityAccessType>(),
            Arg.Any<string>()).Returns(Abstraction.Entities.IdentityServerConfig.SystemPermissions.SystemPermissionRoleType.Writer);

        // Act & Assert
        var ex = Assert.ThrowsAsync<EntityAlreadyExistsException>(async () => await _sut.CreateAsync(_user, createDto));
        Assert.That(ex.Message, Does.Contain($"Application '{clientId}' already contains Secret '{description}'"));
    }
}
