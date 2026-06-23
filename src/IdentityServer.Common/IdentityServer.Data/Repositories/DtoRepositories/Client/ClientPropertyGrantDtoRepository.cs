// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

using AutoMapper;
using System.Security.Claims;
using IdentityServer.Abstraction.Contracts;
using IdentityServer.Abstraction.DTO.Clients;
using IdentityServer.Abstraction.Entities.IdentityServerConfig;
using IdentityServer.Abstraction.Exceptions;
using IdentityServer.Data.DuendeEntityExtensions;
using IdentityServer.Data.Repositories.Storage;
using DataEntities = Duende.IdentityServer.EntityFramework.Entities;

namespace IdentityServer.Data.Repositories.DtoRepositories.Client;

/// <inheritdoc />
internal class ClientPropertyGrantDtoRepository :
    ClientCacheablePropertyBaseDtoRepository<ClientPropertyGrantDtoRead, ClientPropertyGrantDtoCreate, ClientGrantTypeExt>
{
    public ClientPropertyGrantDtoRepository(
        IStorage<ClientExt> clientStorage,
        IStorage<ClientGrantTypeExt> propertyStorage,
        IMapper mapper,
        IPermissionChecker permissionChecker,
        IParentAccessor<ClientGrantTypeExt, ClientExt> parentAccessor,
        ICache<DataEntities.Client> clientCache
        ) : base(clientStorage, propertyStorage, mapper, permissionChecker, parentAccessor, clientCache)
    {
    }

    protected override int GetParentId(ClientPropertyGrantDtoCreate createDto) => createDto.ClientId;

    protected override async Task ThrowIfExistsOrInvalid(ClientPropertyGrantDtoCreate createDto)
    {
        var existingResource = await _propertyStorage.FirstOrDefaultAsync(x => x.ClientId == createDto.ClientId && x.GrantType == createDto.GrantType);
        if (existingResource != null)
        {
            throw new EntityAlreadyExistsException($"Application '{existingResource.ClientId}' already contains Grant '{existingResource.GrantType}'.");
        }
    }

    protected override Task OnBeforeCreateAsync(ClaimsPrincipal user, ClientExt parent, ClientGrantTypeExt propertyToCreate)
    {
        // Check for forbidden Implicit + OfflineAccess
        if (parent.AllowOfflineAccess && string.Equals(propertyToCreate.GrantType, ClientGrantTypeNames.Grant_Implicit, StringComparison.OrdinalIgnoreCase))
        {
            throw new EntityReferenceException("Implicit Grant is not permitted for a client with allowed refresh token for security reasons");
        }

        // Check for incompatible grant pairs
        var selectedGrantTypes = parent.AllowedGrantTypes.Select(g => g.GrantType).ToHashSet(StringComparer.OrdinalIgnoreCase);
        if (!ClientGrantTypeNames.IsGrantCompatible(propertyToCreate.GrantType, selectedGrantTypes))
        {
            throw new EntityReferenceException(
                $"Grant '{propertyToCreate.GrantType}' is not compatible with the already selected grant(s) ({string.Join(", ", ClientGrantTypeNames.GetIncompatibleGrantTypes(propertyToCreate.GrantType, selectedGrantTypes))}).");
        }

        return Task.CompletedTask;
    }

    protected override async Task OnAfterCreateAsync(ClaimsPrincipal user, ClientExt parent, ClientPropertyGrantDtoRead createdProperty)
    {
        // If adding Implicit grant flow, need to update AllowAccessTokenViaBrowser flag
        if (string.Equals(createdProperty.GrantType, ClientGrantTypeNames.Grant_Implicit, StringComparison.OrdinalIgnoreCase))
        {
            parent.AllowAccessTokensViaBrowser = true;
            await _parentStorage.UpdateAsync(parent);
        }
        await base.OnAfterCreateAsync(user, parent, createdProperty);
    }

    override protected Task OnBeforeDeleteAsync(ClaimsPrincipal user, ClientExt parent, ClientGrantTypeExt propertyToRemove)
    {
        if (parent.AllowedGrantTypes.Count == 1)
        {
            throw new EntityReferenceException("Cannot remove the last Grant Type.");
        }
        return Task.CompletedTask;
    }

    protected override async Task OnAfterDeleteAsync(ClaimsPrincipal user, ClientExt parent, ClientGrantTypeExt removedProperty)
    {
        // If removing Implicit grant flow, need to update AllowAccessTokenViaBrowser flag
        if (string.Equals(removedProperty.GrantType, ClientGrantTypeNames.Grant_Implicit, StringComparison.OrdinalIgnoreCase))
        {
            parent.AllowAccessTokensViaBrowser = false;
            await _parentStorage.UpdateAsync(parent);
        }

        await base.OnAfterDeleteAsync(user, parent, removedProperty);
    }
}
