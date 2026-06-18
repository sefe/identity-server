using System.Security.Claims;
using AutoMapper;
using Duende.IdentityServer.EntityFramework.Entities;
using IdentityServer.Abstraction.Contracts;
using IdentityServer.Abstraction.DTO;
using IdentityServer.Abstraction.DTO.ApiResources;
using IdentityServer.Abstraction.Exceptions;
using IdentityServer.Data.DuendeEntityExtensions;
using DataEntities = Duende.IdentityServer.EntityFramework.Entities;

namespace IdentityServer.Data.Repositories.DtoRepositories.ApiResource;

/// <inheritdoc />
internal class ApiResourcePropertyScopeDtoRepository :
    IDtoCreateRepository<ApiResourcePropertyScopeDtoRead, ApiResourcePropertyScopeDtoCreate>,
    IDtoUpdateRepository<ApiResourcePropertyScopeDtoRead, ApiResourcePropertyScopeDtoUpdate>
{
    private readonly IStorage<ApiScopeExt> _apiScopeStorage;
    private readonly IStorage<ApiResourceExt> _apiResourceStorage;
    private readonly IStorage<ApiResourceScopeExt> _apiResourceScopeStorage;
    private readonly IStorage<ClientScopeExt> _clientStorage;
    private readonly IMapper _mapper;
    private readonly IPermissionChecker _permissionChecker;
    private readonly ICache<DataEntities.ApiResource> _apiCache;
    private readonly ICache<ApiScope> _scopeCache;

#pragma warning disable IDE0079 // Remove unnecessary suppression
#pragma warning disable S107 // Reduce the number of parameters
    public ApiResourcePropertyScopeDtoRepository(
        IStorage<ApiScopeExt> apiScopeStorage,
        IStorage<ApiResourceExt> apiResourceStorage,
        IStorage<ApiResourceScopeExt> apiResourceScopeStorage,
        IMapper mapper,
        IPermissionChecker permissionChecker,
        IStorage<ClientScopeExt> clientStorage,
        ICache<DataEntities.ApiResource> apiCache,
        ICache<ApiScope> scopeCache
        )
#pragma warning restore S107 // Reduce the number of parameters
#pragma warning restore IDE0079 // Remove unnecessary suppression
    {
        _apiScopeStorage = apiScopeStorage;
        _apiResourceStorage = apiResourceStorage;
        _apiResourceScopeStorage = apiResourceScopeStorage;
        _mapper = mapper;
        _permissionChecker = permissionChecker;
        _clientStorage = clientStorage;
        _apiCache = apiCache;
        _scopeCache = scopeCache;
    }

    protected static string ParentEntityName => "API Resource";

    public async Task<ApiResourcePropertyScopeDtoRead> CreateAsync(ClaimsPrincipal user, ApiResourcePropertyScopeDtoCreate resource)
    {
        var parentId = resource.ApiResourceId;
        var parent = await _apiResourceStorage.GetByIdAsync(parentId)
            ?? throw new EntityNotFoundException($"API Resource with ID '{parentId}' not found.");

        var parentEnvironmentId = parent.SystemPermissionEnvironmentId;
        await _permissionChecker.GetAccessRoleOrThrowIfNoAccessToEnvAsync(user, parentEnvironmentId, EntityAccessType.Update, $"{ParentEntityName} '{parentId}'");

        // API Scope name must start with the API Resource name
        resource.Name = $"{parent.Name}.{resource.Name}";

        var apiScopeToCreate = _mapper.Map<ApiScopeExt>(resource);
        var storedApiScope = await GetOrCreateApiScope(apiScopeToCreate);

        await ThrowIfExists(resource);

        var storedApiResourceScope = await CreateImplAsync(resource, parent);

        await _apiCache.RemoveAsync(parent.Name);

        // A newly created scope cannot have any clients using it, so pass 0 to avoid unnecessary DB query
        return ToApiResourceScopeDtoRead(storedApiResourceScope, storedApiScope, clientCount: 0);
    }

    public async Task<int?> DeleteAsync(ClaimsPrincipal user, int id)
    {
        var storedApiResourceScope = await _apiResourceScopeStorage.GetByIdAsync(id)
            ?? throw new EntityNotFoundException($"API Resource scope with ID '{id}' was not found.");

        var storedApiScope = await _apiScopeStorage.FirstOrDefaultAsync(s => s.Name == storedApiResourceScope.Scope)
            ?? throw new EntityNotFoundException($"API Scope with Identifier '{storedApiResourceScope.Scope}' was not found.");

        var parentId = storedApiResourceScope.ApiResourceId;
        var parent = await _apiResourceStorage.GetByIdAsync(parentId)
            ?? throw new EntityNotFoundException($"API Resource with ID '{parentId}' not found.");

        var parentEnvironmentId = parent.SystemPermissionEnvironmentId;
        await _permissionChecker.GetAccessRoleOrThrowIfNoAccessToEnvAsync(user, parentEnvironmentId, EntityAccessType.Delete, $"{ParentEntityName} '{parentId}'");

        // Check if the scope is used by any clients
        var clientsScopes = await _clientStorage.ToListAsync(c => c.Scope == storedApiResourceScope.Scope);
        if (clientsScopes.Count != 0)
        {
            throw new EntityReferenceException($"Cannot delete scope '{storedApiResourceScope.Scope}' because it is used by the applications: {string.Join(", ", clientsScopes.Select(_ => $"Client '{_.ClientId}'").Distinct().ToList())}");
        }

        // 2-step approach to capture who deleted the scope, exact timestamp will be recalculated on SaveChangesAsync
        var curTime = DateTime.UtcNow;
        storedApiResourceScope.Updated = curTime;
        await _apiResourceScopeStorage.UpdateAsync(storedApiResourceScope);
        var result = await _apiResourceScopeStorage.DeleteAsync(storedApiResourceScope);

        storedApiScope.Updated = curTime;
        await _apiScopeStorage.UpdateAsync(storedApiScope);
        await _apiScopeStorage.DeleteAsync(storedApiScope);

        // Invalidate caches
        await _apiCache.RemoveAsync(parent.Name);
        await _scopeCache.RemoveAsync(storedApiScope.Name);

        return result;
    }

    public async Task<ApiResourcePropertyScopeDtoRead> UpdateAsync(ClaimsPrincipal user, ApiResourcePropertyScopeDtoUpdate resource)
    {
        if (string.IsNullOrEmpty(resource.DisplayName) && resource.Description == null && resource.Enabled == null && resource.Required == null)
        {
            throw new EntityValidationException("At least one Scope property must be updated.");
        }

        var storedApiResourceScope = await _apiResourceScopeStorage.GetByIdAsync(resource.Id)
            ?? throw new EntityNotFoundException($"API Resource scope with ID '{resource.Id}' was not found.");

        var parentId = storedApiResourceScope.ApiResourceId;
        var parent = await _apiResourceStorage.GetByIdAsync(parentId)
            ?? throw new EntityNotFoundException($"API Resource with ID '{parentId}' not found.");

        var parentEnvironmentId = parent.SystemPermissionEnvironmentId;
        await _permissionChecker.GetAccessRoleOrThrowIfNoAccessToEnvAsync(user, parentEnvironmentId, EntityAccessType.Update, $"{ParentEntityName} '{parentId}'");

        var storedApiScope = await _apiScopeStorage.FirstOrDefaultAsync(s => s.Name == storedApiResourceScope.Scope)
            ?? throw new EntityNotFoundException($"API Scope with Name '{storedApiResourceScope.Scope}' was not found.");

        storedApiScope.DisplayName = resource.DisplayName ?? storedApiScope.DisplayName;
        storedApiScope.Description = resource.Description ?? storedApiScope.Description;
        storedApiScope.Enabled = resource.Enabled ?? storedApiScope.Enabled;
        storedApiScope.Required = resource.Required ?? storedApiScope.Required;

        var apiScopeUpdated = await _apiScopeStorage.UpdateAsync(storedApiScope);

        // Invalidate cache
        await _scopeCache.RemoveAsync(storedApiScope.Name);

        return await ToApiResourceScopeDtoReadAsync(storedApiResourceScope, apiScopeUpdated);
    }

    private async Task<ApiResourceScopeExt> CreateImplAsync(ApiResourcePropertyScopeDtoCreate resource, ApiResourceExt parent)
    {
        return await _apiResourceScopeStorage.AddAsync(new ApiResourceScopeExt
        {
            Id = 0, // Ensure ID is set to 0 for creation
            ApiResource = parent,
            ApiResourceId = parent.Id,
            Scope = resource.Name
        });
    }

    private async Task<ApiScopeExt> GetOrCreateApiScope(ApiScopeExt propertyToCreate)
    {
        var apiScope = await _apiScopeStorage.FirstOrDefaultAsync(x => x.Name == propertyToCreate.Name);
        apiScope ??= await _apiScopeStorage.AddAsync(propertyToCreate);
        return apiScope;
    }

    private async Task ThrowIfExists(ApiResourcePropertyScopeDtoCreate resource)
    {
        var apiResourceScope = await _apiResourceScopeStorage.FirstOrDefaultAsync(s => s.Scope == resource.Name);
        if (apiResourceScope != null)
        {
            throw new EntityAlreadyExistsException($"API Scope with Name '{resource.Name}' already exists.");
        }
    }

    private async Task<ApiResourcePropertyScopeDtoRead> ToApiResourceScopeDtoReadAsync(ApiResourceScope storedApiResourceScope, ApiScopeExt storedApiScope)
    {
        var clientCount = await _clientStorage.CountAsync(c => c.Scope == storedApiScope.Name);
        return ToApiResourceScopeDtoRead(storedApiResourceScope, storedApiScope, clientCount);
    }

    private ApiResourcePropertyScopeDtoRead ToApiResourceScopeDtoRead(ApiResourceScope storedApiResourceScope, ApiScopeExt storedApiScope, int clientCount)
    {
        var mappedApiScope = _mapper.Map<ApiScopeDtoRead>(storedApiScope);
        mappedApiScope.ClientCount = clientCount;

        return new ApiResourcePropertyScopeDtoRead
        {
            ApiScope = mappedApiScope,
            Id = storedApiResourceScope.Id,
            Scope = storedApiResourceScope.Scope,
            ApiResourceId = storedApiResourceScope.ApiResourceId
        };
    }
}
