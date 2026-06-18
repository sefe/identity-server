using System.Security.Claims;
using AutoMapper;
using Microsoft.Extensions.Logging;
using IdentityServer.Abstraction.Contracts;
using IdentityServer.Abstraction.DTO.ApiResources;
using IdentityServer.Abstraction.Entities.IdentityServerConfig.SystemPermissions;
using IdentityServer.Abstraction.Exceptions;
using IdentityServer.Data.DuendeEntityExtensions;

namespace IdentityServer.Data.Repositories.DtoRepositories.ApiResource;

/// <summary>
/// Responsible for DTO cloning and access security checks for <seealso cref="ApiResourceExt"/> entities.
/// </summary>
internal class ApiResourceCloneDtoRepository : ApiResourceDtoRepositoryBase,
    IDtoCloneRepository<ApiResourceDtoRead, ApiResourceDtoClone>
{
    private readonly IStorage<SystemPermissionEnvironment> _sysEnvStorage;
    private readonly IDtoCreateRepository<ApiResourcePropertyScopeDtoRead, ApiResourcePropertyScopeDtoCreate> _apiResourceScopeRepo;

    public ApiResourceCloneDtoRepository(
        IStorage<ApiResourceExt> apiResourceStorage,
        IStorage<ApiScopeExt> apiScopeStorage,
        IStorage<ClientScopeExt> clientScopeStorage,
        IMapper mapper,
        IPermissionChecker permissionChecker,
        IDtoCreateRepository<ApiResourcePropertyScopeDtoRead, ApiResourcePropertyScopeDtoCreate> apiResourceScopeRepo,
        IStorage<SystemPermissionEnvironment> sysEnvStorage,
        ILogger<ApiResourceCloneDtoRepository> logger) : base(apiResourceStorage, apiScopeStorage, clientScopeStorage, mapper, permissionChecker, logger)
    {
        _apiResourceScopeRepo = apiResourceScopeRepo;
        _sysEnvStorage = sysEnvStorage;
    }

    public async Task<ApiResourceDtoRead> CloneAsync(ClaimsPrincipal user, ApiResourceDtoClone resource)
    {
        var roleInTarget = await _permissionChecker.GetAccessRoleOrThrowIfNoAccessToEnvAsync(user, resource.SystemPermissionEnvironmentId, EntityAccessType.Create, "API Resource");

        var entity = await _apiResourceStorage.GetByIdAsync(resource.Id) ?? throw new EntityNotFoundException($"API Resource with Id {resource.Id} was not found.");
        _ = await _permissionChecker.GetAccessRoleOrThrowIfNoAccessToEnvAsync(user, entity.SystemPermissionEnvironmentId, EntityAccessType.Read, entity.ToString()!);

        var existingResource = await _apiResourceStorage.FirstOrDefaultAsync(x => x.Name == resource.Name);
        if (existingResource != null)
        {
            throw new EntityAlreadyExistsException($"API Resource with id '{existingResource.Name}' already exists.");
        }

        var env = await _sysEnvStorage.GetByIdAsync(resource.SystemPermissionEnvironmentId)
            ?? throw new EntityNotFoundException($"System Permission Environment with Id {resource.SystemPermissionEnvironmentId} was not found.");

        var clonedEntity = new ApiResourceExt
        {
            Id = 0,
            Created = DateTime.UtcNow,
            SystemPermissionEnvironmentId = env.Id,
            SystemPermissionEnvironment = env,
            Name = resource.Name,
            DisplayName = resource.DisplayName
        };
        CopyApiResourceProperties(entity, clonedEntity);
        CopyRoles(entity, clonedEntity);

        var storedApiResource = await _apiResourceStorage.AddAsync(clonedEntity);

        await CopyScopesAsync(user, entity, storedApiResource);

        storedApiResource = await _apiResourceStorage.GetByIdAsync(storedApiResource.Id);
        var result = _mapper.Map<ApiResourceDtoRead>(storedApiResource);
        result.AccessLevel = roleInTarget;
        return result;
    }

    private static void CopyApiResourceProperties(ApiResourceExt source, ApiResourceExt target)
    {
        target.Description = source.Description;
        target.Enabled = source.Enabled;
        // Skip secrets
        // Scopes are copied separately as they required ApiScope entities
    }

    private async Task CopyScopesAsync(ClaimsPrincipal user, ApiResourceExt source, ApiResourceExt target)
    {
        foreach (var scope in source.Scopes.Select(s => s.Scope))
        {
            var storedScope = await _apiScopeStorage.FirstOrDefaultAsync(s => s.Name == scope)
                ?? throw new EntityNotFoundException($"API Scope with Name '{scope}' not found.");

            var newScope = new ApiResourcePropertyScopeDtoCreate
            {
                ApiResourceId = target.Id,
                Name = scope[(source.Name.Length + 1)..],
                DisplayName = storedScope.DisplayName,
                Description = storedScope.Description,
                Enabled = storedScope.Enabled,
                Required = storedScope.Required
            };
            await _apiResourceScopeRepo.CreateAsync(user, newScope);
        }
    }

    private static void CopyRoles(ApiResourceExt source, ApiResourceExt target)
    {
        target.Roles = source.Roles.Select(_ => new Entities.Roles.ApiResourceRole() { RoleName = _.RoleName }).ToList();
    }
}
