using System.Security.Claims;
using AutoMapper;
using Duende.IdentityServer.Models;
using Microsoft.Extensions.Options;
using IdentityServer.Abstraction.Configs;
using IdentityServer.Abstraction.Contracts;
using IdentityServer.Abstraction.DTO.ApiResources;
using IdentityServer.Abstraction.Exceptions;
using IdentityServer.Data.DuendeEntityExtensions;
using IdentityServer.Data.Repositories.Storage;
using DataEntities = Duende.IdentityServer.EntityFramework.Entities;

namespace IdentityServer.Data.Repositories.DtoRepositories.ApiResource;

/// <inheritdoc />
internal class ApiResourcePropertySecretDtoRepository :
    ApiResourcePropertyBaseDtoRepository<ApiResourcePropertySecretValueDtoRead, ApiResourcePropertySecretDtoCreate, ApiResourceSecretExt>
{
    private readonly ISecretGeneratorService _secretGenerator;
    private readonly ICache<DataEntities.ApiResource> _apiCache;
    private readonly IOptions<SecretExpirationConfig> _expirationConfig;

    public ApiResourcePropertySecretDtoRepository(
        IStorage<ApiResourceExt> apiStorage,
        IStorage<ApiResourceSecretExt> propertyStorage,
        IMapper mapper,
        IPermissionChecker permissionChecker,
        ISecretGeneratorService secretGenerator,
        IParentAccessor<ApiResourceSecretExt, ApiResourceExt> parentAccessor,
        ICache<DataEntities.ApiResource> apiCache,
        IOptions<SecretExpirationConfig> expirationConfig
        )
        : base(apiStorage, propertyStorage, mapper, permissionChecker, parentAccessor)
    {
        _secretGenerator = secretGenerator;
        _apiCache = apiCache;
        _expirationConfig = expirationConfig;
    }

    protected override int GetParentId(ApiResourcePropertySecretDtoCreate createDto) => createDto.ApiResourceId;

    protected override async Task ThrowIfExistsOrInvalid(ApiResourcePropertySecretDtoCreate createDto)
    {
        var existingResource = await _propertyStorage.FirstOrDefaultAsync(x => x.ApiResourceId == createDto.ApiResourceId && x.Description == createDto.Description);
        if (existingResource != null)
        {
            throw new EntityAlreadyExistsException($"API Resource '{existingResource.ApiResourceId}' already contains Secret '{existingResource.Description}'.");
        }

        // Validate validity period against configured maximum
        if (createDto.ValidityPeriodYears > _expirationConfig.Value.MaxValidityYears)
        {
            throw new EntityValidationException($"Validity period cannot exceed {_expirationConfig.Value.MaxValidityYears} years.");
        }
    }

    protected override async Task<ApiResourcePropertySecretValueDtoRead> CreateImplAsync(ClaimsPrincipal user, ApiResourcePropertySecretDtoCreate resource, ApiResourceExt apiResource)
    {
        // only the hash of the secret value is stored in the DB
        var secretValue = _secretGenerator.GenerateSecureSecret();

        var propertyToCreate = _mapper.Map<ApiResourceSecretExt>(resource);
        propertyToCreate.Value = secretValue.Sha256();
        propertyToCreate.Preview = secretValue[..4];

        // Calculate expiration date based on validity period in years
        propertyToCreate.Expiration = DateTime.UtcNow.AddYears(resource.ValidityPeriodYears);

        var storedProperty = await _propertyStorage.AddAsync(propertyToCreate);
        var createdPropertyDto = _mapper.Map<ApiResourcePropertySecretValueDtoRead>(storedProperty);

        // return the original value to the caller
        createdPropertyDto.Value = secretValue;

        await _apiCache.RemoveAsync(apiResource.Name);

        return createdPropertyDto;
    }

    protected override async Task OnAfterDeleteAsync(ClaimsPrincipal user, ApiResourceExt parent, ApiResourceSecretExt removedProperty)
    {
        await _apiCache.RemoveAsync(parent.Name);
    }
}
