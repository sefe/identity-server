// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

using System.Security.Claims;
using AutoMapper;
using Duende.IdentityServer.Models;
using Microsoft.Extensions.Options;
using IdentityServer.Abstraction.Configs;
using IdentityServer.Abstraction.Contracts;
using IdentityServer.Abstraction.DTO.Clients;
using IdentityServer.Abstraction.Exceptions;
using IdentityServer.Data.DuendeEntityExtensions;
using IdentityServer.Data.Repositories.Storage;
using DataEntities = Duende.IdentityServer.EntityFramework.Entities;

namespace IdentityServer.Data.Repositories.DtoRepositories.Client;

/// <inheritdoc />
internal class ClientPropertySecretDtoRepository :
    ClientCacheablePropertyBaseDtoRepository<ClientPropertySecretValueDtoRead, ClientPropertySecretDtoCreate, ClientSecretExt>
{
    private readonly ISecretGeneratorService _secretGenerator;
    private readonly IOptions<SecretExpirationConfig> _expirationConfig;

    public ClientPropertySecretDtoRepository(
        IStorage<ClientExt> clientStorage,
        IStorage<ClientSecretExt> propertyStorage,
        IMapper mapper,
        IPermissionChecker permissionChecker,
        ISecretGeneratorService secretGenerator,
        IParentAccessor<ClientSecretExt, ClientExt> parentAccessor,
        ICache<DataEntities.Client> clientCache,
        IOptions<SecretExpirationConfig> expirationConfig
        ) : base(clientStorage, propertyStorage, mapper, permissionChecker, parentAccessor, clientCache)
    {
        _secretGenerator = secretGenerator;
        _expirationConfig = expirationConfig;
    }

    protected override int GetParentId(ClientPropertySecretDtoCreate createDto) => createDto.ClientId;

    protected override async Task ThrowIfExistsOrInvalid(ClientPropertySecretDtoCreate createDto)
    {
        var existingResource = await _propertyStorage.FirstOrDefaultAsync(x => x.ClientId == createDto.ClientId && x.Description == createDto.Description);
        if (existingResource != null)
        {
            throw new EntityAlreadyExistsException($"Application '{existingResource.ClientId}' already contains Secret '{existingResource.Description}'.");
        }

        // Validate validity period against configured maximum
        if (createDto.ValidityPeriodYears > _expirationConfig.Value.MaxValidityYears)
        {
            throw new EntityValidationException($"Validity period cannot exceed {_expirationConfig.Value.MaxValidityYears} years.");
        }
    }

    protected override async Task<ClientPropertySecretValueDtoRead> CreateImplAsync(ClaimsPrincipal user, ClientPropertySecretDtoCreate resource, ClientExt client)
    {
        // only the hash of the secret value is stored in the DB
        var secretValue = _secretGenerator.GenerateSecureSecret();

        var propertyToCreate = _mapper.Map<ClientSecretExt>(resource);
        propertyToCreate.Value = secretValue.Sha256();
        propertyToCreate.Preview = secretValue[..4];

        // Calculate expiration date based on validity period in years
        propertyToCreate.Expiration = DateTime.UtcNow.AddYears(resource.ValidityPeriodYears);

        var storedProperty = await _propertyStorage.AddAsync(propertyToCreate);
        var createdPropertyDto = _mapper.Map<ClientPropertySecretValueDtoRead>(storedProperty);

        // return the original value to the caller
        createdPropertyDto.Value = secretValue;

        await base.OnAfterCreateAsync(user, client, createdPropertyDto);

        return createdPropertyDto;
    }
}
