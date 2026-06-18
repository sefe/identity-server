using System.Linq.Expressions;
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
/// Responsible for DTO mapping and access security checks for <seealso cref="ApiResourceExt"/> entities.
/// </summary>
internal class ApiResourceDtoRepository : ApiResourceDtoRepositoryBase,
    IDtoCreateRepository<ApiResourceDtoRead, ApiResourceDtoCreate>,
    IDtoReadRepository<ApiResourceDtoRead>,
    IDtoListRepository<ApiResourceShortDtoRead, ApiResourceExt>,
    IDtoUpdateRepository<ApiResourceDtoRead, ApiResourceDtoUpdate>
{
    private readonly ICache<Duende.IdentityServer.EntityFramework.Entities.ApiResource> _apiCache;
    private readonly IApiResourceAuditService _auditService;

    public ApiResourceDtoRepository(
        IStorage<ApiResourceExt> apiStorage,
        IStorage<ApiScopeExt> apiScopeStorage,
        IStorage<ClientScopeExt> clientScopeStorage,
        IMapper mapper,
        IPermissionChecker permissionChecker,
        ICache<Duende.IdentityServer.EntityFramework.Entities.ApiResource> apiCache,
        IApiResourceAuditService auditService,
        ILogger<ApiResourceDtoRepository> logger)
        : base(apiStorage, apiScopeStorage, clientScopeStorage, mapper, permissionChecker, logger)
    {
        _apiCache = apiCache;
        _auditService = auditService;
    }

    public async Task<ApiResourceDtoRead> CreateAsync(ClaimsPrincipal user, ApiResourceDtoCreate resource)
    {
        var role = await _permissionChecker.GetAccessRoleOrThrowIfNoAccessToEnvAsync(user, resource.SystemPermissionEnvironmentId, EntityAccessType.Create, "API Resource");

        var existingResource = await _apiResourceStorage.FirstOrDefaultAsync(x => x.Name == resource.Name);
        if (existingResource != null)
        {
            throw new EntityAlreadyExistsException($"API Resource '{existingResource.Name}' already exists.");
        }

        var apiResource = _mapper.Map<ApiResourceExt>(resource);

        apiResource.Created = DateTime.UtcNow;

        var storedApiResource = await _apiResourceStorage.AddAsync(apiResource);
        var result = _mapper.Map<ApiResourceDtoRead>(storedApiResource);
        result.AccessLevel = role;
        return result;
    }

    public async Task<int?> DeleteAsync(ClaimsPrincipal user, int id)
    {
        var entity = await _apiResourceStorage.GetByIdAsync(id);
        if (entity == null) { return null; }

        await _permissionChecker.GetAccessRoleOrThrowIfNoAccessToEnvAsync(user, entity.SystemPermissionEnvironmentId, EntityAccessType.Delete, entity.ToString()!);

        await ThrowIfAnyScopesAreInUseAsync(entity);

        // Update and Delete associated ApiScope entities
        await DeleteApiScopesAsync(entity);

        // 2-step approach to capture who deleted the Api Resource and all nested entities
        SetUpdatedAuditFieldsRecursive(entity);
        await _apiResourceStorage.UpdateAsync(entity);
        var removedId = await _apiResourceStorage.DeleteAsync(entity);

        await _apiCache.RemoveAsync(entity.Name);

        return removedId;
    }

    public async Task<ApiResourceDtoRead> UpdateAsync(ClaimsPrincipal user, ApiResourceDtoUpdate resource)
    {
        var currentApiResource = await _apiResourceStorage.GetByIdAsync(resource.Id) ?? throw new EntityNotFoundException($"API Resource with Id {resource.Id} was not found.");
        var role = await _permissionChecker.GetAccessRoleOrThrowIfNoAccessToEnvAsync(user, currentApiResource.SystemPermissionEnvironmentId, EntityAccessType.Update, currentApiResource.ToString()!);

        currentApiResource.Updated = DateTime.UtcNow;
        currentApiResource.DisplayName = resource.DisplayName ?? currentApiResource.DisplayName;
        currentApiResource.Description = resource.Description ?? currentApiResource.Description;
        currentApiResource.Enabled = resource.Enabled ?? currentApiResource.Enabled;

        var storedApiResource = await _apiResourceStorage.UpdateAsync(currentApiResource);
        var result = _mapper.Map<ApiResourceDtoRead>(storedApiResource);
        result.AccessLevel = role;

        if (result.Scopes?.Count > 0)
        {
            await PopulateApiScopesAsync(result.Scopes);
        }

        await _apiCache.RemoveAsync(currentApiResource.Name);

        result.Updated = DateTime.UtcNow;
        result.UpdateReason = "Api Resource";

        return result;
    }

    public Task<IQueryable<ApiResourceShortDtoRead>> GetQueryableAsync(ClaimsPrincipal user)
    {
        return GetQueryableAsync(user, null);
    }

    public async Task<IQueryable<ApiResourceShortDtoRead>> GetQueryableAsync(ClaimsPrincipal user, Expression<Func<ApiResourceExt, bool>>? filter)
    {
        // 1. Pre-fetch async dependencies (permissions)
        HashSet<int>? allowedEnvIds = null;
        if (!user.IsInRole(Abstraction.Constants.RoleNames.Admin))
        {
            allowedEnvIds = await _permissionChecker.GetAllAccessiblePermissionEnvironmentsAsync(user, SystemPermissionRoleType.Reader);
        }

        // 2. Build the deferred query
        var query = _apiResourceStorage.ShallowQuery();

        // 3. Apply filter
        if (filter != null)
        {
            query = query.Where(filter);
        }

        // 4. Project to DTO (EF Core will translate this to SQL)
        return query.Select(item => new ApiResourceShortDtoRead
        {
            Id = item.Id,
            Name = item.Name,
            DisplayName = item.DisplayName,
            SystemPermissionId = item.SystemPermissionEnvironment.SystemPermissionId,
            SystemPermissionName = item.SystemPermissionEnvironment.SystemPermission.Name,
            SystemPermissionEnvironmentId = item.SystemPermissionEnvironmentId,
            SystemPermissionEnvironmentName = item.SystemPermissionEnvironment.Environment,
            SystemPermissionEnvironmentOwnersList = item.SystemPermissionEnvironment.Permissions.Where(p => p.RoleType == SystemPermissionRoleType.Writer).Select(p => p.Name).OrderBy(n => n).ToList(),
            AccessLevel = allowedEnvIds == null || allowedEnvIds.Contains(item.SystemPermissionEnvironmentId)
                ? SystemPermissionRoleType.Reader
                : SystemPermissionRoleType.None,
            Created = item.Created,
            CreatedBy = item.CreatedBy,
            Updated = item.Updated,
            UpdatedBy = item.UpdatedBy
        });
    }

    public async Task<ApiResourceDtoRead?> GetByIdAsync(ClaimsPrincipal user, int id)
    {
        var entity = await _apiResourceStorage.GetByIdAsync(id);
        if (entity == null)
        {
            return null;
        }

        var role = await _permissionChecker.GetAccessRoleOrThrowIfNoAccessToEnvAsync(user, entity.SystemPermissionEnvironmentId, EntityAccessType.Read, entity.ToString()!);

        var result = _mapper.Map<ApiResourceDtoRead>(entity);
        result.AccessLevel = role;

        if (result.Scopes?.Count > 0)
        {
            await PopulateApiScopesAsync(result.Scopes);
        }

        var lastModifiedInfo = await _auditService.GetLastModifiedByIdAsync(id);
        if (lastModifiedInfo != null)
        {
            result.Updated = lastModifiedInfo.LastModified;
            result.UpdateReason = lastModifiedInfo.Reason;
        }

        return result;
    }

    private async Task ThrowIfAnyScopesAreInUseAsync(ApiResourceExt entity)
    {
        if (entity.Scopes == null || entity.Scopes.Count < 1)
        {
            return;
        }

        var scopeNames = entity.Scopes.Select(s => s.Scope).ToHashSet(StringComparer.Ordinal);
        var inUseScopes = await _clientScopeStorage.ToListAsync(s => scopeNames.Contains(s.Scope));
        if (inUseScopes.Count > 0)
        {
            throw new EntityReferenceException($"API Resource '{entity.Name}' cannot be deleted because its scope(s) " +
                $"'{string.Join("', '", inUseScopes.Select(s => s.Scope).Distinct())}' are in use by application(s) ID " +
                $"'{string.Join("', '", inUseScopes.Select(s => s.ClientId).Distinct())}'.");
        }
    }

    private static void SetUpdatedAuditFieldsRecursive(ApiResourceExt entity)
    {
        var updatedTime = DateTime.UtcNow;
        entity.Updated = updatedTime;
        SetUpdatedAuditFieldForRoles(entity, updatedTime);
        SetUpdatedAuditFieldForSecrets(entity, updatedTime);
        SetUpdatedAuditFieldForScopes(entity, updatedTime);
    }

    private static void SetUpdatedAuditFieldForScopes(ApiResourceExt entity, DateTime updatedTime)
    {
        if (entity.Scopes != null)
        {
            foreach (var scope in entity.Scopes)
            {
                if (scope is ApiResourceScopeExt extScope)
                {
                    extScope.Updated = updatedTime;
                }
            }
        }
    }

    private static void SetUpdatedAuditFieldForSecrets(ApiResourceExt entity, DateTime updatedTime)
    {
        if (entity.Secrets != null)
        {
            foreach (var secret in entity.Secrets)
            {
                if (secret is ApiResourceSecretExt extSecret)
                {
                    extSecret.Updated = updatedTime;
                }
            }
        }
    }

    private static void SetUpdatedAuditFieldForRoles(ApiResourceExt entity, DateTime updatedTime)
    {
        if (entity.Roles != null)
        {
            foreach (var role in entity.Roles)
            {
                role.Updated = updatedTime;
                if (role.Mappings != null)
                {
                    foreach (var mapping in role.Mappings)
                    {
                        mapping.Updated = updatedTime;
                    }
                }
            }
        }
    }

    /// <summary>
    /// Delete the actual ApiScope entities associated with this ApiResource.
    /// The ApiResourceScope relationship entities will be deleted automatically via cascade delete.
    /// </summary>
    private async Task DeleteApiScopesAsync(ApiResourceExt entity)
    {
        if (entity.Scopes == null || entity.Scopes.Count == 0)
        {
            return;
        }

        var scopeNames = entity.Scopes.Select(s => s.Scope).ToHashSet(StringComparer.Ordinal);
        var apiScopesToDelete = await _apiScopeStorage.ToListAsync(s => scopeNames.Contains(s.Name));

        // Apply audit fields before deletion
        var currTime = DateTime.UtcNow;
        foreach (var apiScope in apiScopesToDelete)
        {
            apiScope.Updated = currTime;
            await _apiScopeStorage.UpdateAsync(apiScope);
        }

        await _apiScopeStorage.DeleteAsync(apiScopesToDelete);
    }
}
