using System.Security.Claims;
using AutoMapper;
using IdentityServer.Abstraction.Contracts;
using IdentityServer.Abstraction.DTO.ApiResources;
using IdentityServer.Abstraction.Exceptions;
using IdentityServer.Data.DuendeEntityExtensions;
using IdentityServer.Data.Entities.Roles;
using IdentityServer.Data.Repositories.Storage;

namespace IdentityServer.Data.Repositories.DtoRepositories.ApiResource;

/// <inheritdoc />
internal class ApiResourcePropertyRoleDtoRepository :
    ApiResourcePropertyBaseDtoRepository<ApiResourcePropertyRoleDtoRead, ApiResourcePropertyRoleDtoCreate, ApiResourceRole>
{
    public ApiResourcePropertyRoleDtoRepository(
        IStorage<ApiResourceExt> apiStorage,
        IStorage<ApiResourceRole> propertyStorage,
        IMapper mapper,
        IPermissionChecker permissionChecker,
        IParentAccessor<ApiResourceRole, ApiResourceExt> parentAccessor
        ) : base(apiStorage, propertyStorage, mapper, permissionChecker, parentAccessor)
    {
    }

    protected override int GetParentId(ApiResourcePropertyRoleDtoCreate createDto) => createDto.ApiResourceId;

    protected override async Task ThrowIfExistsOrInvalid(ApiResourcePropertyRoleDtoCreate createDto)
    {
        var existingResource = await _propertyStorage.FirstOrDefaultAsync(
            x => x.ApiResourceId == createDto.ApiResourceId && x.RoleName == createDto.RoleName);
        if (existingResource != null)
        {
            throw new EntityAlreadyExistsException($"API Resource '{existingResource.ApiResourceId}' already contains Role '{existingResource.RoleName}'.");
        }
    }

    protected override async Task OnBeforeDeleteAsync(ClaimsPrincipal user, ApiResourceExt parent, ApiResourceRole propertyToRemove)
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
