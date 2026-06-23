// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

using System.Security.Claims;
using AutoMapper;
using IdentityServer.Abstraction.Contracts;
using IdentityServer.Abstraction.DTO;
using IdentityServer.Abstraction.Exceptions;
using IdentityServer.Data.Repositories.Storage;

namespace IdentityServer.Data.Repositories.DtoRepositories;

#pragma warning disable IDE0079 // Remove unnecessary suppression
#pragma warning disable S2436 // Reduce the number of generic parameters

/// <summary>
/// Responsible for DTO mapping and access security checks of <typeparamref name="TProperty"/> entities.
/// </summary>
internal abstract class BasePropertyDtoRepository<TRead, TCreate, TParent, TProperty> :
    IDtoCreateRepository<TRead, TCreate>
    where TRead : IDtoRead
    where TCreate : IDtoCreate
    where TParent : class
    where TProperty : class, IHasUpdatedInfo
#pragma warning restore S2436 // Reduce the number of generic parameters
#pragma warning restore IDE0079 // Remove unnecessary suppression
{
    protected readonly IStorage<TParent> _parentStorage;
    protected readonly IStorage<TProperty> _propertyStorage;
    protected readonly IPermissionChecker _permissionChecker;
    protected readonly IMapper _mapper;

    private readonly IParentAccessor<TProperty, TParent> _parentAccessor;

    protected BasePropertyDtoRepository(
        IStorage<TParent> parentStorage,
        IStorage<TProperty> propertyStorage,
        IMapper mapper,
        IPermissionChecker permissionChecker,
        IParentAccessor<TProperty, TParent> parentAccessor
        )
    {
        _parentStorage = parentStorage;
        _propertyStorage = propertyStorage;
        _mapper = mapper;
        _permissionChecker = permissionChecker;
        _parentAccessor = parentAccessor;
    }

    /// <summary>
    /// Singular parent entity name, used for error messages.
    /// </summary>
    protected abstract string ParentEntityName { get; set; }

    protected abstract int GetParentId(TCreate createDto);
    protected abstract Task ThrowIfExistsOrInvalid(TCreate createDto);

    protected virtual Task OnBeforeCreateAsync(ClaimsPrincipal user, TParent parent, TProperty propertyToCreate) { return Task.CompletedTask; }
    protected virtual Task OnAfterCreateAsync(ClaimsPrincipal user, TParent parent, TRead createdProperty) { return Task.CompletedTask; }
    protected virtual Task OnBeforeDeleteAsync(ClaimsPrincipal user, TParent parent, TProperty propertyToRemove) { return Task.CompletedTask; }
    protected virtual Task OnAfterDeleteAsync(ClaimsPrincipal user, TParent parent, TProperty removedProperty) { return Task.CompletedTask; }

    public async Task<TRead> CreateAsync(ClaimsPrincipal user, TCreate resource)
    {
        var parentId = GetParentId(resource);
        var parent = await _parentStorage.GetByIdAsync(parentId) ?? throw new EntityNotFoundException($"{ParentEntityName} with ID '{parentId}' not found.");

        var parentEnvironmentId = _parentAccessor.GetParentEnvironmentId(parent);
        await _permissionChecker.GetAccessRoleOrThrowIfNoAccessToEnvAsync(user, parentEnvironmentId, EntityAccessType.Update, $"{ParentEntityName} '{parentId}'");

        await ThrowIfExistsOrInvalid(resource);

        return await CreateImplAsync(user, resource, parent);
    }

    protected virtual async Task<TRead> CreateImplAsync(ClaimsPrincipal user, TCreate resource, TParent parent)
    {
        var propertyToCreate = _mapper.Map<TProperty>(resource);
        await OnBeforeCreateAsync(user, parent, propertyToCreate);
        var storedProperty = await _propertyStorage.AddAsync(propertyToCreate);
        var createdPropertyDto = _mapper.Map<TRead>(storedProperty);
        await OnAfterCreateAsync(user, parent, createdPropertyDto);
        return createdPropertyDto;
    }

    public async Task<int?> DeleteAsync(ClaimsPrincipal user, int id)
    {
        var storedProperty = await _propertyStorage.GetByIdAsync(id);
        if (storedProperty == null)
        {
            return null;
        }

        var parentId = _parentAccessor.GetParentId(storedProperty);
        var parent = await _parentStorage.GetByIdAsync(parentId) ?? throw new EntityNotFoundException($"{ParentEntityName} with ID '{parentId}' not found.");

        var parentEnvironmentId = _parentAccessor.GetParentEnvironmentId(parent);
        await _permissionChecker.GetAccessRoleOrThrowIfNoAccessToEnvAsync(user, parentEnvironmentId, EntityAccessType.Update, $"{ParentEntityName} '{parentId}'");

        await OnBeforeDeleteAsync(user, parent, storedProperty);

        // 2-step approach to capture who deleted the property
        storedProperty.Updated = DateTime.UtcNow;
        await _propertyStorage.UpdateAsync(storedProperty);
        var result = await _propertyStorage.DeleteAsync(storedProperty);
        await OnAfterDeleteAsync(user, parent, storedProperty);
        return result;
    }
}

