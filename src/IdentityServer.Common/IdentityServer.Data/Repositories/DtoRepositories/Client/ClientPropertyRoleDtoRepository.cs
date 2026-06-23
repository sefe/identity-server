// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

using System.Security.Claims;
using AutoMapper;
using IdentityServer.Abstraction.Contracts;
using IdentityServer.Abstraction.DTO.Clients;
using IdentityServer.Abstraction.Exceptions;
using IdentityServer.Data.DuendeEntityExtensions;
using IdentityServer.Data.Entities.Roles;
using IdentityServer.Data.Repositories.Storage;

namespace IdentityServer.Data.Repositories.DtoRepositories.Client;

/// <inheritdoc />
internal class ClientPropertyRoleDtoRepository :
    ClientPropertyBaseDtoRepository<ClientPropertyRoleDtoRead, ClientPropertyRoleDtoCreate, ClientRole>
{
    public ClientPropertyRoleDtoRepository(
        IStorage<ClientExt> clientStorage,
        IStorage<ClientRole> propertyStorage,
        IMapper mapper,
        IPermissionChecker permissionChecker,
        IParentAccessor<ClientRole, ClientExt> parentAccessor
        ) : base(clientStorage, propertyStorage, mapper, permissionChecker, parentAccessor)
    {
    }

    protected override int GetParentId(ClientPropertyRoleDtoCreate createDto) => createDto.ClientId;

    protected override async Task ThrowIfExistsOrInvalid(ClientPropertyRoleDtoCreate createDto)
    {
        var existingResource = await _propertyStorage.FirstOrDefaultAsync(
            x => x.ClientId == createDto.ClientId && x.RoleName == createDto.RoleName);
        if (existingResource != null)
        {
            throw new EntityAlreadyExistsException($"Application '{existingResource.ClientId}' already contains Role '{existingResource.RoleName}'.");
        }
    }

    protected override async Task OnBeforeDeleteAsync(ClaimsPrincipal user, ClientExt parent, ClientRole propertyToRemove)
    {
        // Update audit timestamps on the role and all its mappings before deletion
        var updatedTime = DateTime.UtcNow;
        propertyToRemove.Updated = updatedTime;
        if (propertyToRemove.Mappings != null)
        {
            foreach (var mapping in propertyToRemove.Mappings)
            {
                mapping.Updated = updatedTime;
            }
        }
        await _propertyStorage.UpdateAsync(propertyToRemove);
    }
}
