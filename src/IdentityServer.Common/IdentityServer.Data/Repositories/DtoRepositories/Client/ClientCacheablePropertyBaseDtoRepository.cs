using AutoMapper;
using System.Security.Claims;
using IdentityServer.Abstraction.Contracts;
using IdentityServer.Abstraction.DTO;
using IdentityServer.Data.DuendeEntityExtensions;
using IdentityServer.Data.Repositories.Storage;
using DataEntities = Duende.IdentityServer.EntityFramework.Entities;

namespace IdentityServer.Data.Repositories.DtoRepositories.Client;

#pragma warning disable IDE0079 // Remove unnecessary suppression
#pragma warning disable S2436 // Reduce the number of generic parameters
internal abstract class ClientCacheablePropertyBaseDtoRepository<TRead, TCreate, TProperty> :
    ClientPropertyBaseDtoRepository<TRead, TCreate, TProperty>
    where TRead : IDtoRead
    where TCreate : IDtoCreate
    where TProperty : class, IHasUpdatedInfo
{
#pragma warning restore S2436 // Reduce the number of generic parameters
#pragma warning restore IDE0079 // Remove unnecessary suppression
    protected readonly ICache<DataEntities.Client> _clientCache;

    protected ClientCacheablePropertyBaseDtoRepository(
        IStorage<ClientExt> parentStorage,
        IStorage<TProperty> propertyStorage,
        IMapper mapper,
        IPermissionChecker permissionChecker,
        IParentAccessor<TProperty, ClientExt> parentAccessor,
        ICache<DataEntities.Client> clientCache
        ) : base(parentStorage, propertyStorage, mapper, permissionChecker, parentAccessor)
    {
        _clientCache = clientCache;
    }

    protected override async Task OnAfterCreateAsync(ClaimsPrincipal user, ClientExt parent, TRead createdProperty)
    {
        await _clientCache.RemoveAsync(parent.ClientId.ToString());
    }

    protected override async Task OnAfterDeleteAsync(ClaimsPrincipal user, ClientExt parent, TProperty removedProperty)
    {
        await _clientCache.RemoveAsync(parent.ClientId.ToString());
    }
}
