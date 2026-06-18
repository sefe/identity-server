using System.Linq.Expressions;
using System.Security.Claims;
using AutoMapper;
using IdentityServer.Abstraction.Contracts;
using IdentityServer.Abstraction.DTO.SystemPermissions;
using IdentityServer.Abstraction.Entities.IdentityServerConfig.SystemPermissions;
using IdentityServer.Abstraction.Exceptions;
using IdentityServer.Abstraction.Extensions;
using IdentityServer.Data.DuendeEntityExtensions;

namespace IdentityServer.Data.Repositories.DtoRepositories;

/// <summary>
/// Responsible for DTO mapping and access security checks for <seealso cref="SystemPermissionEnvironment"/> entities.
/// </summary>
internal class SystemPermissionEnvironmentDtoRepository :
    IDtoCreateRepository<SystemPermissionEnvironmentDtoRead, SystemPermissionEnvironmentDtoCreate>,
    IDtoReadRepository<SystemPermissionEnvironmentDtoRead>,
    IDtoListRepository<SystemPermissionEnvironmentDtoRead, SystemPermissionEnvironment>
{
    private readonly IStorage<SystemPermission> _systemStorage;
    private readonly IStorage<SystemPermissionEnvironment> _envStorage;
    private readonly IStorage<SystemPermissionRole> _roleStorage;
    private readonly IStorage<ClientExt> _clientStorage;
    private readonly IStorage<ApiResourceExt> _apiResourceStorage;
    private readonly IMapper _mapper;
    private readonly IPermissionChecker _permissionChecker;

    public SystemPermissionEnvironmentDtoRepository(
        IStorage<SystemPermission> systemStorage,
        IStorage<SystemPermissionEnvironment> envStorage,
        IStorage<SystemPermissionRole> roleStorage,
        IStorage<ClientExt> clientStorage,
        IStorage<ApiResourceExt> apiResourceStorage,
        IMapper mapper,
        IPermissionChecker permissionChecker)
    {
        _systemStorage = systemStorage;
        _envStorage = envStorage;
        _roleStorage = roleStorage;
        _clientStorage = clientStorage;
        _apiResourceStorage = apiResourceStorage;
        _mapper = mapper;
        _permissionChecker = permissionChecker;
    }

    public async Task<SystemPermissionEnvironmentDtoRead?> GetByIdAsync(ClaimsPrincipal user, int id)
    {
        var entity = await _envStorage.GetByIdAsync(id);
        if (entity == null) { return null; }

        // Null user can be passed by controller to avoid security checks for partial info retrieval (e.g., environment contacts).
        if (user != null)
        {
            await _permissionChecker.GetAccessRoleOrThrowIfNoAccessToEnvAsync(user, entity.Id, EntityAccessType.Read, entity.Environment);
        }

        var result = _mapper.Map<SystemPermissionEnvironmentDtoRead>(entity);

        (result.ClientCount, result.ApiResourceCount) = await IsInUse(entity.Id);

        return result;
    }

    public Task<IQueryable<SystemPermissionEnvironmentDtoRead>> GetQueryableAsync(ClaimsPrincipal user)
    {
        return GetQueryableAsync(user, null);
    }

    /// <summary>
    /// Returns writeable environments for the current user, used in paged retrieval for system permission environment dropdown list in UI.
    /// </summary>
    /// <param name="user">Current user</param>
    /// <param name="filter">Filter</param>
    /// <returns>List of writeable environments.</returns>
    public async Task<IQueryable<SystemPermissionEnvironmentDtoRead>> GetQueryableAsync(ClaimsPrincipal user, Expression<Func<SystemPermissionEnvironment, bool>>? filter)
    {
        // 1. Pre-fetch async dependencies (permissions)
        var userObjectId = user.GetUserObjectId();
        var isAdmin = user.IsInRole(Abstraction.Constants.RoleNames.Admin);

        // 2. Build the deferred query
        var query = _envStorage.ShallowQuery().Where(x => isAdmin || x.Permissions.Any(p => p.RoleType == SystemPermissionRoleType.Writer && p.OId == userObjectId));

        // 3. Apply filter
        if (filter != null)
        {
            query = query.Where(filter);
        }

        // 4. Project to DTO (EF Core will translate this to SQL)
        return query.Select(item => new SystemPermissionEnvironmentDtoRead
        {
            Id = item.Id,
            SystemPermissionId = item.SystemPermissionId,
            Environment = item.Environment,
            SystemPermissionName = item.SystemPermission.Name
            // Permissions (and thus Owners) are excluded here to reduce response size
            // ClientCount and ApiResourceCount are populated in post-processing (not needed for UI dropdown case)
        });
    }

    public async Task PostProcess(List<SystemPermissionEnvironmentDtoRead>? items)
    {
        if (items == null || items.Count == 0)
        {
            return;
        }
        foreach (var item in items)
        {
            (item.ClientCount, item.ApiResourceCount) = await IsInUse(item.Id);
        }
    }

    public async Task<SystemPermissionEnvironmentDtoRead> CreateAsync(ClaimsPrincipal user, SystemPermissionEnvironmentDtoCreate resource)
    {
        var system = await _systemStorage.GetByIdAsync(resource.SystemPermissionId) ?? throw new EntityReferenceException($"System Permission '{resource.SystemPermissionId}' doesn't exist!");

        _permissionChecker.GetAccessRoleOrThrowIfNoAccessToSystem(user, system, EntityAccessType.Update, "environments");

        if (system.Environments.Any(e => e.Environment == resource.Environment))
        {
            throw new EntityAlreadyExistsException($"A System Permission Environment '{resource.Environment}' already exists for System Permission ID '{resource.SystemPermissionId}'.");
        }

        var toBeCreated = _mapper.Map<SystemPermissionEnvironment>(resource);
        var created = await _envStorage.AddAsync(toBeCreated);

        // For each new Environment add the existing user as Writer
        var defaultPermission = await _roleStorage.AddAsync(new SystemPermissionRole
        {
            Name = user.GetUserName(),
            OId = user.GetUserObjectId(),
            SystemPermissionEnvironmentId = created.Id,
            RoleType = SystemPermissionRoleType.Writer
        });

        // As described in https://learn.microsoft.com/en-us/ef/core/saving/#approach-1-change-tracking-and-savechanges
        // EF uses an internal change tracker on all loaded entities.
        // After the Environment object creation, it is still tracked; thus depending on the EF backing storage it may lead to background object mutation.
        // The addition of the role calls SaveChanges() and the relationship can be reflected instantly on the already acquired Environment object.
        if (!created.Permissions.Contains(defaultPermission))
        {
            created.Permissions.Add(defaultPermission);
        }

        return _mapper.Map<SystemPermissionEnvironmentDtoRead>(created);
    }

    public async Task<int?> DeleteAsync(ClaimsPrincipal user, int id)
    {
        var entity = await _envStorage.GetByIdAsync(id);
        if (entity == null) { return null; }

        await _permissionChecker.GetAccessRoleOrThrowIfNoAccessToEnvAsync(user, entity.Id, EntityAccessType.Delete, entity.Environment);

        if (await IsInUse(entity.Id) != (0, 0))
        {
            throw new EntityReferenceException($"The System Permission Environment '{entity.Environment}' is already assigned to one or more Applications and/or API Resources, please delete all references before removing the environment.");
        }

        // 2-step approach to capture who deleted the environment
        SetUpdatedAuditFields(entity);
        await _envStorage.UpdateAsync(entity);
        return await _envStorage.DeleteAsync(entity);
    }

    private async Task<(int, int)> IsInUse(int envId)
    {
        return (await _clientStorage.CountAsync(x => x.SystemPermissionEnvironmentId == envId),
               await _apiResourceStorage.CountAsync(x => x.SystemPermissionEnvironmentId == envId));
    }

    private static void SetUpdatedAuditFields(SystemPermissionEnvironment environment)
    {
        var updatedTime = DateTime.UtcNow;
        environment.Updated = updatedTime;
        if (environment.Permissions != null)
        {
            foreach (var permission in environment.Permissions)
            {
                permission.Updated = updatedTime;
            }
        }
    }
}
