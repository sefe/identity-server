// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

using System.Linq.Expressions;
using System.Security.Claims;
using IdentityServer.Abstraction.DTO;
using IdentityServer.Abstraction.DTO.Import;

namespace IdentityServer.Abstraction.Contracts;

public interface IDtoListRepository<TRead, TEntity> where TRead : IDtoRead
{
    /// <summary>
    /// Returns a queryable data source.
    /// </summary>
    /// <remarks>The query is NOT executed until enumerated (e.g., by Telerik's ToDataSourceResultAsync).</remarks>
    /// <param name="user">Current user claims principal</param>
    /// <returns>A Task that resolves to an IQueryable with deferred execution</returns>
    Task<IQueryable<TRead>> GetQueryableAsync(ClaimsPrincipal user);
    /// <summary>
    /// Returns a queryable data source.
    /// </summary>
    /// <remarks>The query is NOT executed until enumerated (e.g., by Telerik's ToDataSourceResultAsync).</remarks>
    /// <param name="user">Current user claims principal</param>
    /// <param name="filter">Filter expression</param>
    /// <returns>A Task that resolves to an IQueryable with deferred execution</returns>
    Task<IQueryable<TRead>> GetQueryableAsync(ClaimsPrincipal user, Expression<Func<TEntity, bool>>? filter);
    /// <summary>
    /// Populates additional data on the list of items after retrieval.
    /// </summary>
    /// <remarks>Some DTOs require additional data that cannot be translated to SQL.</remarks>
    /// <param name="items">List of items to populate</param>
    /// <returns>When completed</returns>
    Task PostProcess(List<TRead>? items) => Task.CompletedTask;
}

public interface IDtoParentListRepository<TRead> where TRead : IDtoRead
{
    Task<IEnumerable<TRead>> GetAllByParentIdAsync(ClaimsPrincipal user, int parentId);
}

public interface IDtoReadRepository<TRead> where TRead : IDtoRead
{
    Task<TRead?> GetByIdAsync(ClaimsPrincipal user, int id);
}

public interface IDtoCreateRepository<TRead, TCreate> where TRead : IDtoRead where TCreate : IDtoCreate
{
    Task<TRead> CreateAsync(ClaimsPrincipal user, TCreate resource);
    Task<int?> DeleteAsync(ClaimsPrincipal user, int id);
}

public interface IDtoImportRepository<TImport> where TImport : IDtoImport
{
    Task<OperationStatus> ImportAsync(ClaimsPrincipal user, int id, TImport resource);
    Task<OperationStatus> ValidateImportAsync(ClaimsPrincipal user, int id, TImport resource);
}

public interface IDtoUpdateRepository<TRead, TUpdate> where TRead : IDtoRead where TUpdate : IDtoUpdate
{
    Task<TRead> UpdateAsync(ClaimsPrincipal user, TUpdate resource);
}

public interface IDtoCloneRepository<TRead, TClone> where TRead : IDtoRead where TClone : IDtoClone
{
    Task<TRead> CloneAsync(ClaimsPrincipal user, TClone resource);
}
