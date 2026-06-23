// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

using System.Security.Claims;
using AutoMapper;
using IdentityServer.Abstraction.Contracts;
using IdentityServer.Abstraction.DTO.Clients;
using IdentityServer.Abstraction.Exceptions;
using IdentityServer.Data.Entities.Roles;
using IdentityServer.Data.Repositories.Storage;
using IdentityServer.Data.Services;

namespace IdentityServer.Data.Repositories.DtoRepositories.Client;

/// <inheritdoc />
/// <remarks>
/// Itermediate repository for <seealso cref="ClientRoleMapping"/> children of <seealso cref="ClientRole"/>.
/// </remarks>
internal class ClientPropertyRoleMappingDtoRepository :
    BasePropertyDtoRepository<ClientPropertyRoleMappingDtoRead, ClientPropertyRoleMappingDtoCreate, ClientRole, ClientRoleMapping>
{
    private readonly IRoleMappingValidationService _roleMappingValidationService;

    public ClientPropertyRoleMappingDtoRepository(
        IStorage<ClientRole> roleStorage,
        IStorage<ClientRoleMapping> propertyStorage,
        IMapper mapper,
        IPermissionChecker permissionChecker,
        IParentAccessor<ClientRoleMapping, ClientRole> parentAccessor,
        IRoleMappingValidationService roleMappingValidationService
        ) : base(roleStorage, propertyStorage, mapper, permissionChecker, parentAccessor)
    {
        _roleMappingValidationService = roleMappingValidationService;
    }

    protected override string ParentEntityName { get; set; } = "Application Role";

    protected override int GetParentId(ClientPropertyRoleMappingDtoCreate createDto) => createDto.ClientRoleId;

    protected override async Task ThrowIfExistsOrInvalid(ClientPropertyRoleMappingDtoCreate createDto)
    {
        var existingResource = await _propertyStorage.FirstOrDefaultAsync(
            x => x.ClientRoleId == createDto.ClientRoleId && x.MappingType == createDto.MappingType && x.Value == createDto.Value);
        if (existingResource != null)
        {
            throw new EntityAlreadyExistsException(
                $"Application Role Mapping of type '{existingResource.MappingType}' with value '{existingResource.Value}'" +
                $" already already exists for Role '{existingResource.Role?.RoleName ?? existingResource.ClientRoleId.ToString()}'.");
        }
    }

    protected override async Task OnBeforeCreateAsync(ClaimsPrincipal user, ClientRole parent, ClientRoleMapping propertyToCreate)
    {
        var validationSummary = await _roleMappingValidationService.ValidateClientRoleMappingAsync(propertyToCreate);

        if (validationSummary.HasErrors)
        {
            throw new EntityValidationException(validationSummary.ToString());
        }

        await base.OnBeforeCreateAsync(user, parent, propertyToCreate);
    }
}
