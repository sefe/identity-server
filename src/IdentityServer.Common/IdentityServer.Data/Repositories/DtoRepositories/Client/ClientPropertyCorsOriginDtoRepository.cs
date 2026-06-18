using AutoMapper;
using Duende.IdentityServer.EntityFramework.Services;
using Duende.IdentityServer.Stores;
using System.Security.Claims;
using IdentityServer.Abstraction.Contracts;
using IdentityServer.Abstraction.DTO.Clients;
using IdentityServer.Abstraction.Exceptions;
using IdentityServer.Data.DuendeEntityExtensions;
using IdentityServer.Data.Repositories.Storage;
using DataEntities = Duende.IdentityServer.EntityFramework.Entities;

namespace IdentityServer.Data.Repositories.DtoRepositories.Client;

/// <inheritdoc />
internal class ClientPropertyCorsOriginDtoRepository :
    ClientCacheablePropertyBaseDtoRepository<ClientPropertyCorsOriginDtoRead, ClientPropertyCorsOriginDtoCreate, ClientCorsOriginExt>
{
    private readonly ICache<CachingCorsPolicyService<CorsPolicyService>.CorsCacheEntry> _corsCache;

    public ClientPropertyCorsOriginDtoRepository(
        IStorage<ClientExt> clientStorage,
        IStorage<ClientCorsOriginExt> propertyStorage,
        IMapper mapper,
        IPermissionChecker permissionChecker,
        IParentAccessor<ClientCorsOriginExt, ClientExt> parentAccessor,
        ICache<CachingCorsPolicyService<CorsPolicyService>.CorsCacheEntry> corsCache,
        ICache<DataEntities.Client> clientCache
        ) : base(clientStorage, propertyStorage, mapper, permissionChecker, parentAccessor, clientCache)
    {
        _corsCache = corsCache;
    }

    protected override int GetParentId(ClientPropertyCorsOriginDtoCreate createDto) => createDto.ClientId;

    protected override async Task ThrowIfExistsOrInvalid(ClientPropertyCorsOriginDtoCreate createDto)
    {
        var existingResource = await _propertyStorage.FirstOrDefaultAsync(x => x.ClientId == createDto.ClientId && x.Origin == createDto.Origin);
        if (existingResource != null)
        {
            throw new EntityAlreadyExistsException($"Application '{existingResource.ClientId}' already contains CORS Origin '{existingResource.Origin}'.");
        }
    }

    protected override async Task OnAfterCreateAsync(ClaimsPrincipal user, ClientExt parent, ClientPropertyCorsOriginDtoRead createdProperty)
    {
        // CORS origins are cached as they are first encountered as allowed or forbidden based on the configuration at the moment of the request.
        // If a user makes a request with a not-yet-configured Origin, the request will be blocked and the Origin will be cached as `allowed = false`.
        // Therefore it's important to invalidate CORS cache for the new origin for subsequent user requests to succeed.
        await _corsCache.RemoveAsync(createdProperty.Origin);
        await base.OnAfterCreateAsync(user, parent, createdProperty);
    }

    protected override async Task OnAfterDeleteAsync(ClaimsPrincipal user, ClientExt parent, ClientCorsOriginExt removedProperty)
    {
        await _corsCache.RemoveAsync(removedProperty.Origin);
        await base.OnAfterDeleteAsync(user, parent, removedProperty);
    }
}
