using System.Security.Claims;
using AutoMapper;
using IdentityServer.Abstraction.Contracts;
using IdentityServer.Abstraction.DTO.ApiResources;
using IdentityServer.Abstraction.Exceptions;
using IdentityServer.Data.Entities.Roles;
using IdentityServer.Data.Repositories.Storage;
using IdentityServer.Data.Services;

namespace IdentityServer.Data.Repositories.DtoRepositories.ApiResource;

/// <inheritdoc />
/// <remarks>
/// Itermediate repository for <seealso cref="RoleMapping"/> children of <seealso cref="ApiResourceRole"/>.
/// </remarks>
internal class ApiResourcePropertyRoleMappingDtoRepository :
    BasePropertyDtoRepository<ApiResourcePropertyRoleMappingDtoRead, ApiResourcePropertyRoleMappingDtoCreate, ApiResourceRole, RoleMapping>
{
    private readonly IRoleMappingValidationService _roleMappingValidationService;

    public ApiResourcePropertyRoleMappingDtoRepository(
        IStorage<ApiResourceRole> roleStorage,
        IStorage<RoleMapping> propertyStorage,
        IMapper mapper,
        IPermissionChecker permissionChecker,
        IParentAccessor<RoleMapping, ApiResourceRole> parentAccessor,
        IRoleMappingValidationService roleMappingValidationService
        ) : base(roleStorage, propertyStorage, mapper, permissionChecker, parentAccessor)
    {
        _roleMappingValidationService = roleMappingValidationService;
    }

    protected override string ParentEntityName { get; set; } = "API Resource Role";

    protected override int GetParentId(ApiResourcePropertyRoleMappingDtoCreate createDto) => createDto.ApiResourceRoleId;

    protected override async Task ThrowIfExistsOrInvalid(ApiResourcePropertyRoleMappingDtoCreate createDto)
    {
        var existingResource = await _propertyStorage.FirstOrDefaultAsync(
            x => x.ApiResourceRoleId == createDto.ApiResourceRoleId && x.MappingType == createDto.MappingType && x.Value == createDto.Value);
        if (existingResource != null)
        {
            throw new EntityAlreadyExistsException(
                $"API Resource Role Mapping of type '{existingResource.MappingType}' with value '{existingResource.Value}'" +
                $" already already exists for Role '{existingResource.Role?.RoleName ?? existingResource.ApiResourceRoleId.ToString()}'.");
        }
    }

    protected override async Task OnBeforeCreateAsync(ClaimsPrincipal user, ApiResourceRole parent, RoleMapping propertyToCreate)
    {
        var validationSummary = await _roleMappingValidationService.ValidateApiRoleMappingAsync(propertyToCreate);

        if (validationSummary.HasErrors)
        {
            throw new EntityValidationException(validationSummary.ToString());
        }

        await base.OnBeforeCreateAsync(user, parent, propertyToCreate);
    }
}
