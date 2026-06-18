using System.Security.Claims;
using AutoMapper;
using Duende.IdentityServer.EntityFramework.Entities;
using IdentityServer.Abstraction.Contracts;
using IdentityServer.Abstraction.DTO;
using IdentityServer.Abstraction.DTO.Clients;
using IdentityServer.Abstraction.Entities.IdentityServerConfig;
using IdentityServer.Abstraction.Exceptions;
using IdentityServer.Data.DuendeEntityExtensions;
using IdentityServer.Data.Repositories.Storage;
using DataEntities = Duende.IdentityServer.EntityFramework.Entities;

namespace IdentityServer.Data.Repositories.DtoRepositories.Client;

/// <inheritdoc />
internal class ClientPropertyScopeDtoRepository :
    ClientCacheablePropertyBaseDtoRepository<ClientPropertyScopeDtoRead, ClientPropertyScopeDtoCreate, ClientScopeExt>
{
    private readonly IStorage<ApiScopeExt> _apiScopeStorage;
    private readonly IStorage<ApiResourceExt> _apiResourceStorage;

    public ClientPropertyScopeDtoRepository(
        IStorage<ClientExt> clientStorage,
        IStorage<ClientScopeExt> propertyStorage,
        IStorage<ApiScopeExt> apiScopeStorage,
        IStorage<ApiResourceExt> apiResourceStorage,
        IMapper mapper,
        IPermissionChecker permissionChecker,
        IParentAccessor<ClientScopeExt, ClientExt> parentAccessor,
        ICache<DataEntities.Client> clientCache
        ) : base(clientStorage, propertyStorage, mapper, permissionChecker, parentAccessor, clientCache)
    {
        _apiScopeStorage = apiScopeStorage;
        _apiResourceStorage = apiResourceStorage;
    }

    protected override int GetParentId(ClientPropertyScopeDtoCreate createDto) => createDto.ClientId;

    protected override async Task OnAfterCreateAsync(ClaimsPrincipal user, ClientExt parent, ClientPropertyScopeDtoRead resource)
    {
        var apiScope = await _apiScopeStorage.FirstOrDefaultAsync(x => x.Name == resource.Scope);
        resource.ApiScope = _mapper.Map<ApiScopeDtoRead>(apiScope);
        await base.OnAfterCreateAsync(user, parent, resource);
    }

    protected override async Task ThrowIfExistsOrInvalid(ClientPropertyScopeDtoCreate createDto)
    {
        var existingResource = await _propertyStorage.FirstOrDefaultAsync(x => x.ClientId == createDto.ClientId && x.Scope == createDto.Scope);
        if (existingResource != null)
        {
            throw new EntityAlreadyExistsException($"Application '{existingResource.ClientId}' already contains scope '{existingResource.Scope}'.");
        }
    }

    protected override async Task OnBeforeCreateAsync(ClaimsPrincipal user, ClientExt parent, ClientScopeExt propertyToCreate)
    {
        await ValidateClientScopesPermissions(user, parent.SystemPermissionEnvironmentId, propertyToCreate);
    }

    protected override Task OnBeforeDeleteAsync(ClaimsPrincipal user, ClientExt parent, ClientScopeExt propertyToRemove)
    {
        if (propertyToRemove.Scope == OidcScopeNames.OpenIdScope)
        {
            parent.AllowOfflineAccess = false;
        }
        return Task.CompletedTask;
    }

    // make sure user adds only valid scopes from the Client SPE
    private async Task ValidateClientScopesPermissions(ClaimsPrincipal user, int systemPermissionEnvId, ClientScope entity)
    {
        if (OidcScopeNames.OidcStandardScopeMapping.ContainsKey(entity.Scope))
        {
            return;
        }

        await ThrowIfNonExistentScope(entity.Scope);
        await ThrowIfInaccessibleScope(entity.Scope, systemPermissionEnvId, user);
    }

    private async Task ThrowIfNonExistentScope(string requestedScopeName)
    {
        if (!await _apiScopeStorage.AnyAsync(x => x.Name == requestedScopeName))
        {
            throw new EntityReferenceException($"Scope '{requestedScopeName}' doesn't exist.");
        }
    }

    // only allow scopes from the same system permission environment as the client
    private async Task ThrowIfInaccessibleScope(string requestedScopeName, int systemPermissionEnvId, ClaimsPrincipal user)
    {
        if (user.IsInRole(Abstraction.Constants.RoleNames.Admin))
        {
            return;
        }

        var apiResource = await _apiResourceStorage.FirstOrDefaultAsync(_ => _.Scopes.Any(s => s.Scope == requestedScopeName))
            ?? throw new EntityReferenceException($"Scope '{requestedScopeName}' doesn't exist.");

        if (apiResource.SystemPermissionEnvironmentId != systemPermissionEnvId)
        {
            throw new EntityAccessException(
                user,
                $"the scope '{requestedScopeName}'",
                EntityAccessType.Update,
                "Only scopes from client system permission environment are allowed.");
        }
    }
}
