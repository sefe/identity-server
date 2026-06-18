using AutoMapper;
using IdentityServer.Abstraction.Contracts;
using IdentityServer.Abstraction.DTO;
using IdentityServer.Data.DuendeEntityExtensions;
using IdentityServer.Data.Repositories.Storage;

namespace IdentityServer.Data.Repositories.DtoRepositories.Client;

#pragma warning disable IDE0079 // Remove unnecessary suppression
#pragma warning disable S2436 // Reduce the number of generic parameters

internal abstract class ClientPropertyBaseDtoRepository<TRead, TCreate, TProperty>
    : BasePropertyDtoRepository<TRead, TCreate, ClientExt, TProperty>
    where TRead : IDtoRead
    where TCreate : IDtoCreate
    where TProperty : class, IHasUpdatedInfo
{
    protected ClientPropertyBaseDtoRepository(
        IStorage<ClientExt> parentStorage,
        IStorage<TProperty> propertyStorage,
        IMapper mapper,
        IPermissionChecker permissionChecker,
        IParentAccessor<TProperty, ClientExt> parentAccessor
        ) : base(parentStorage, propertyStorage, mapper, permissionChecker, parentAccessor)
    {
    }

    protected override string ParentEntityName { get; set; } = "Application";
}

#pragma warning restore S2436 // Reduce the number of generic parameters
#pragma warning restore IDE0079 // Remove unnecessary suppression
