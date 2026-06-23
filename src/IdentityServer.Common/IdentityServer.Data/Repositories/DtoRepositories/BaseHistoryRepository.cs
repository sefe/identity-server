// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

using System.Security.Claims;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Logging;
using IdentityServer.Abstraction;
using IdentityServer.Abstraction.Contracts;
using IdentityServer.Abstraction.DTO.History;
using IdentityServer.Data.DbContexts;
using IdentityServer.Data.Services;

namespace IdentityServer.Data.Repositories.DtoRepositories;

/// <summary>
/// Base class for history repositories providing common functionality for querying temporal tables.
/// </summary>
internal abstract class BaseHistoryRepository
{
    protected readonly IDbContextFactory<IdentityServerConfigurationDbContext> _contextFactory;
    protected readonly IPermissionChecker _permissionChecker;
    protected readonly ILogger _logger;
    private readonly IHistoryService _historyService;

    /// <summary>
    /// Gets the name of the property that links child entities to the parent entity.
    /// For example: "ClientId", "ApiResourceId", "SystemPermissionId".
    /// </summary>
    protected abstract string ParentIdPropertyName { get; }

    protected BaseHistoryRepository(
        IDbContextFactory<IdentityServerConfigurationDbContext> contextFactory,
        IPermissionChecker permissionChecker,
        ILogger logger,
        IHistoryService historyService)
    {
        _contextFactory = contextFactory;
        _permissionChecker = permissionChecker;
        _logger = logger;
        _historyService = historyService;
    }

    /// <summary>
    /// Generic method to get add/remove history for entities related to a parent entity.
    /// These entities only have creation and deletion events, no field updates.
    /// </summary>
    protected async Task<List<HistoryEntryDto>> GetAddRemoveEntityHistoryAsync<TEntity>(
        int parentId,
        Func<TEntity, string> getIdentifier,
        Func<TEntity, List<FieldChangeDto>>? getCreationFields = null)
        where TEntity : class, IHasId<int>, IHasPeriodData, IHasCreatedInfo, IHasUpdatedInfo
    {
        await using var context = await _contextFactory.CreateDbContextAsync();

        var allVersions = await context.Set<TEntity>()
            .TemporalAll()
            .Where(e => EF.Property<int>(e, ParentIdPropertyName) == parentId)
            .ToListAsync();

        return _historyService.ProcessAddRemoveEntityVersions(
            allVersions,
            getIdentifier,
            getCreationFields);
    }

    /// <summary>
    /// Logs the completion of a history retrieval operation.
    /// </summary>
    protected void LogHistoryRetrieval(string entityType, int entityId, ClaimsPrincipal user, long startTimestamp, int recordCount)
    {
        var elapsedMs = CommonHelpers.GetElapsedMilliseconds(startTimestamp);
        _logger.LogDebug("Retrieved history for {EntityType} {EntityId} by user {User} in {DurationMs} ms with {HistoryRecords} records",
            entityType, entityId, user.Identity?.Name, elapsedMs, recordCount);
    }

    /// <summary>
    /// Executes multiple history queries in parallel and merges results sorted by timestamp descending.
    /// </summary>
    protected static async Task<List<HistoryEntryDto>> ExecuteHistoryQueriesAndMergeAsync(params Task<List<HistoryEntryDto>>[] historyTasks)
    {
        var results = await Task.WhenAll(historyTasks);

        return results
            .SelectMany(events => events)
            .OrderByDescending(e => e.Timestamp)
            .ToList();
    }

    /// <summary>
    /// Creates a standardized history response.
    /// </summary>
    protected static HistoryResponseDto CreateHistoryResponse(int entityId, string entityName, List<HistoryEntryDto> history)
    {
        return new HistoryResponseDto
        {
            EntityId = entityId,
            EntityName = entityName,
            History = history
        };
    }
}
