// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

using AutoMapper;
using IdentityServer.Abstraction.Contracts;
using IdentityServer.Abstraction.DTO;
using IdentityServer.Data.DuendeEntityExtensions;
using IdentityServer.Data.Repositories.Storage;

namespace IdentityServer.Data.Repositories.DtoRepositories.ApiResource;

#pragma warning disable IDE0079 // Remove unnecessary suppression
#pragma warning disable S2436 // Reduce the number of generic parameters
#pragma warning restore IDE0079 // Remove unnecessary suppression

internal abstract class ApiResourcePropertyBaseDtoRepository<TRead, TCreate, TProperty>
    : BasePropertyDtoRepository<TRead, TCreate, ApiResourceExt, TProperty>
    where TRead : IDtoRead
    where TCreate : IDtoCreate
    where TProperty : class, IHasUpdatedInfo
{
    protected ApiResourcePropertyBaseDtoRepository(
        IStorage<ApiResourceExt> parentStorage,
        IStorage<TProperty> propertyStorage,
        IMapper mapper,
        IPermissionChecker permissionChecker,
        IParentAccessor<TProperty, ApiResourceExt> parentAccessor
        ) : base(parentStorage, propertyStorage, mapper, permissionChecker, parentAccessor)
    {
    }

    protected override string ParentEntityName { get; set; } = "API Resource";
}

#pragma warning disable IDE0079 // Remove unnecessary suppression
#pragma warning restore S2436 // Reduce the number of generic parameters
#pragma warning restore IDE0079 // Remove unnecessary suppression
