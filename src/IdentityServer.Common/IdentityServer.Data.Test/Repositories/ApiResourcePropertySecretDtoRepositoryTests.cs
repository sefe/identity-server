using System.Security.Claims;
using AutoMapper;
using Duende.IdentityServer.EntityFramework.Entities;
using Duende.IdentityServer.Models;
using Microsoft.Extensions.Options;
using NSubstitute;
using IdentityServer.Abstraction.Configs;
using IdentityServer.Abstraction.Contracts;
using IdentityServer.Abstraction.DTO.ApiResources;
using IdentityServer.Abstraction.Exceptions;
using IdentityServer.Data.DuendeEntityExtensions;
using IdentityServer.Data.Repositories.DtoRepositories.ApiResource;
using IdentityServer.Data.Repositories.Storage;
using IdentityServer.Tests.Common.Builders;

namespace IdentityServer.Data.Test.Repositories;

[TestFixture]
public class ApiResourcePropertySecretDtoRepositoryTests
{
    private IStorage<ApiResourceExt> _apiStorage;
    private IStorage<ApiResourceSecretExt> _propertyStorage;
    private IMapper _mapper;
    private IPermissionChecker _permissionChecker;
    private ISecretGeneratorService _secretGenerator;
    private IParentAccessor<ApiResourceSecretExt, ApiResourceExt> _parentAccessor;
    private ICache<Duende.IdentityServer.EntityFramework.Entities.ApiResource> _apiCache;
    private IOptions<SecretExpirationConfig> _expirationConfig;
    private ApiResourcePropertySecretDtoRepository _sut;
    private ClaimsPrincipal _user;

    [SetUp]
    public void SetUp()
    {
        _apiStorage = Substitute.For<IStorage<ApiResourceExt>>();
        _propertyStorage = Substitute.For<IStorage<ApiResourceSecretExt>>();
        _mapper = Substitute.For<IMapper>();
        _permissionChecker = Substitute.For<IPermissionChecker>();
        _secretGenerator = Substitute.For<ISecretGeneratorService>();
        _parentAccessor = Substitute.For<IParentAccessor<ApiResourceSecretExt, ApiResourceExt>>();
        _apiCache = Substitute.For<ICache<Duende.IdentityServer.EntityFramework.Entities.ApiResource>>();
        _expirationConfig = Options.Create(new SecretExpirationConfig { MaxValidityYears = 2 });

        _sut = new ApiResourcePropertySecretDtoRepository(
            _apiStorage,
            _propertyStorage,
            _mapper,
            _permissionChecker,
            _secretGenerator,
            _parentAccessor,
            _apiCache,
            _expirationConfig);

        _user = new ClaimsPrincipal();
    }

    [Test]
    public async Task CreateAsync_WithValidityPeriodExceedingMaximum_ThrowsEntityValidationException()
    {
        // Arrange
        var apiResourceId = 1;
        var createDto = new ApiResourcePropertySecretDtoCreate
        {
            ApiResourceId = apiResourceId,
            Description = "Test Secret",
            ValidityPeriodYears = 3 // Exceeds configured maximum of 2
        };

        var apiResource = new ApiResourceExtBuilder("test-api")
            .WithId(apiResourceId)
            .Build();

        _propertyStorage.FirstOrDefaultAsync(Arg.Any<System.Linq.Expressions.Expression<Func<ApiResourceSecretExt, bool>>>())
            .Returns((ApiResourceSecretExt)null);

        _apiStorage.GetByIdAsync(apiResourceId).Returns(apiResource);
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
        var apiResourceId = 1;
        var createDto = new ApiResourcePropertySecretDtoCreate
        {
            ApiResourceId = apiResourceId,
            Description = "Test Secret",
            ValidityPeriodYears = 2 // Equal to configured maximum
        };

        var apiResource = new ApiResourceExtBuilder("test-api")
            .WithId(apiResourceId)
            .Build();

        var secretValue = "generated-secret-value";
        var expectedExpiration = DateTime.UtcNow.AddYears(2);
        var createdSecret = new ApiResourceSecretExt
        {
            ApiResourceId = apiResourceId,
            Description = "Test Secret",
            Value = secretValue.Sha256(),
            Preview = secretValue.Substring(0, 4),
            Expiration = expectedExpiration
        };

        _propertyStorage.FirstOrDefaultAsync(Arg.Any<System.Linq.Expressions.Expression<Func<ApiResourceSecretExt, bool>>>())
            .Returns((ApiResourceSecretExt)null);

        _apiStorage.GetByIdAsync(apiResourceId).Returns(apiResource);
        _permissionChecker.GetAccessRoleOrThrowIfNoAccessToEnvAsync(
            Arg.Any<ClaimsPrincipal>(),
            Arg.Any<int>(),
            Arg.Any<EntityAccessType>(),
            Arg.Any<string>()).Returns(Abstraction.Entities.IdentityServerConfig.SystemPermissions.SystemPermissionRoleType.Writer);

        _secretGenerator.GenerateSecureSecret().Returns(secretValue);
        _mapper.Map<ApiResourceSecretExt>(createDto).Returns(new ApiResourceSecretExt { ApiResourceId = apiResourceId, Description = "Test Secret" });
        _propertyStorage.AddAsync(Arg.Any<ApiResourceSecretExt>()).Returns(createdSecret);
        _mapper.Map<ApiResourcePropertySecretValueDtoRead>(createdSecret).Returns(new ApiResourcePropertySecretValueDtoRead
        {
            ApiResourceId = apiResourceId,
            Description = "Test Secret",
            Expiration = expectedExpiration
        });

        // Act
        var result = await _sut.CreateAsync(_user, createDto);

        // Assert
        Assert.That(result, Is.Not.Null);
        await _propertyStorage.Received(1).AddAsync(Arg.Is<ApiResourceSecretExt>(s => 
            s.Expiration.HasValue && 
            s.Expiration.Value >= expectedExpiration.AddSeconds(-5) && 
            s.Expiration.Value <= expectedExpiration.AddSeconds(5)));
    }

    [Test]
    public async Task CreateAsync_WithValidityPeriodBelowMaximum_DoesNotThrow()
    {
        // Arrange
        var apiResourceId = 1;
        var createDto = new ApiResourcePropertySecretDtoCreate
        {
            ApiResourceId = apiResourceId,
            Description = "Test Secret",
            ValidityPeriodYears = 1 // Below configured maximum
        };

        var apiResource = new ApiResourceExtBuilder("test-api")
            .WithId(apiResourceId)
            .Build();

        var secretValue = "generated-secret-value";
        var expectedExpiration = DateTime.UtcNow.AddYears(1);
        var createdSecret = new ApiResourceSecretExt
        {
            ApiResourceId = apiResourceId,
            Description = "Test Secret",
            Value = secretValue.Sha256(),
            Preview = secretValue.Substring(0, 4),
            Expiration = expectedExpiration
        };

        _propertyStorage.FirstOrDefaultAsync(Arg.Any<System.Linq.Expressions.Expression<Func<ApiResourceSecretExt, bool>>>())
            .Returns((ApiResourceSecretExt)null);

        _apiStorage.GetByIdAsync(apiResourceId).Returns(apiResource);
        _permissionChecker.GetAccessRoleOrThrowIfNoAccessToEnvAsync(
            Arg.Any<ClaimsPrincipal>(),
            Arg.Any<int>(),
            Arg.Any<EntityAccessType>(),
            Arg.Any<string>()).Returns(Abstraction.Entities.IdentityServerConfig.SystemPermissions.SystemPermissionRoleType.Writer);

        _secretGenerator.GenerateSecureSecret().Returns(secretValue);
        _mapper.Map<ApiResourceSecretExt>(createDto).Returns(new ApiResourceSecretExt { ApiResourceId = apiResourceId, Description = "Test Secret" });
        _propertyStorage.AddAsync(Arg.Any<ApiResourceSecretExt>()).Returns(createdSecret);
        _mapper.Map<ApiResourcePropertySecretValueDtoRead>(createdSecret).Returns(new ApiResourcePropertySecretValueDtoRead
        {
            ApiResourceId = apiResourceId,
            Description = "Test Secret",
            Expiration = expectedExpiration
        });

        // Act
        var result = await _sut.CreateAsync(_user, createDto);

        // Assert
        Assert.That(result, Is.Not.Null);
        await _propertyStorage.Received(1).AddAsync(Arg.Is<ApiResourceSecretExt>(s => 
            s.Expiration.HasValue && 
            s.Expiration.Value >= expectedExpiration.AddSeconds(-5) && 
            s.Expiration.Value <= expectedExpiration.AddSeconds(5)));
    }

    [Test]
    public async Task CreateAsync_SetsExpirationDateCorrectly()
    {
        // Arrange
        var apiResourceId = 1;
        var validityYears = 2;
        var createDto = new ApiResourcePropertySecretDtoCreate
        {
            ApiResourceId = apiResourceId,
            Description = "Test Secret",
            ValidityPeriodYears = validityYears
        };

        var apiResource = new ApiResourceExtBuilder("test-api")
            .WithId(apiResourceId)
            .Build();

        var secretValue = "generated-secret-value";
        var timeBeforeCreate = DateTime.UtcNow;

        _propertyStorage.FirstOrDefaultAsync(Arg.Any<System.Linq.Expressions.Expression<Func<ApiResourceSecretExt, bool>>>())
            .Returns((ApiResourceSecretExt)null);

        _apiStorage.GetByIdAsync(apiResourceId).Returns(apiResource);
        _permissionChecker.GetAccessRoleOrThrowIfNoAccessToEnvAsync(
            Arg.Any<ClaimsPrincipal>(),
            Arg.Any<int>(),
            Arg.Any<EntityAccessType>(),
            Arg.Any<string>()).Returns(Abstraction.Entities.IdentityServerConfig.SystemPermissions.SystemPermissionRoleType.Writer);

        _secretGenerator.GenerateSecureSecret().Returns(secretValue);
        _mapper.Map<ApiResourceSecretExt>(createDto).Returns(new ApiResourceSecretExt { ApiResourceId = apiResourceId, Description = "Test Secret" });

        ApiResourceSecretExt capturedSecret = null;
        _propertyStorage.AddAsync(Arg.Do<ApiResourceSecretExt>(s => capturedSecret = s))
            .Returns(callInfo => callInfo.Arg<ApiResourceSecretExt>());
        
        _mapper.Map<ApiResourcePropertySecretValueDtoRead>(Arg.Any<ApiResourceSecretExt>())
            .Returns(callInfo => new ApiResourcePropertySecretValueDtoRead
            {
                ApiResourceId = apiResourceId,
                Description = "Test Secret",
                Expiration = callInfo.Arg<ApiResourceSecretExt>().Expiration
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
        var apiResourceId = 1;
        var description = "Duplicate Secret";
        var createDto = new ApiResourcePropertySecretDtoCreate
        {
            ApiResourceId = apiResourceId,
            Description = description,
            ValidityPeriodYears = 2
        };

        var existingSecret = new ApiResourceSecretExt
        {
            ApiResourceId = apiResourceId,
            Description = description
        };

        _propertyStorage.FirstOrDefaultAsync(Arg.Any<System.Linq.Expressions.Expression<Func<ApiResourceSecretExt, bool>>>())
            .Returns(existingSecret);

        var apiResource = new ApiResourceExtBuilder("test-api")
            .WithId(apiResourceId)
            .Build();

        _apiStorage.GetByIdAsync(apiResourceId).Returns(apiResource);
        _permissionChecker.GetAccessRoleOrThrowIfNoAccessToEnvAsync(
            Arg.Any<ClaimsPrincipal>(),
            Arg.Any<int>(),
            Arg.Any<EntityAccessType>(),
            Arg.Any<string>()).Returns(Abstraction.Entities.IdentityServerConfig.SystemPermissions.SystemPermissionRoleType.Writer);

        // Act & Assert
        var ex = Assert.ThrowsAsync<EntityAlreadyExistsException>(async () => await _sut.CreateAsync(_user, createDto));
        Assert.That(ex.Message, Does.Contain($"API Resource '{apiResourceId}' already contains Secret '{description}'"));
    }
}
