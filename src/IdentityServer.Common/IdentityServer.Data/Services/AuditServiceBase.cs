// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

using System.Data;
using System.Diagnostics;
using Microsoft.Data.SqlClient;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Logging;
using IdentityServer.Abstraction;
using IdentityServer.Abstraction.Contracts;
using IdentityServer.Data.DbContexts;

namespace IdentityServer.Data.Services;

/// <summary>
/// Base class for audit services that retrieve historic data about changes made to entities using stored procedures.
/// </summary>
internal abstract class AuditServiceBase : IAuditService
{
    private readonly IdentityServerConfigurationDbContext _dbContext;
    private readonly ILogger _logger;
    private const string _sqlCommandParameterName = "@Ids";
    /// <summary>
    /// Naming matches the user-defined table type in the database.
    /// </summary>
    private const string _sqlIntIdListTypeName = "dbo.IntIdList";

    protected abstract string SqlRawCommand { get; }

    protected AuditServiceBase(IdentityServerConfigurationDbContext dbContext, ILogger logger)
    {
        _dbContext = dbContext;
        _logger = logger;
    }

    /// <summary>
    /// Gets the last modified data for specific entities.
    /// </summary>
    /// <param name="entityIds">List of entity IDs. If empty, returns all entities.</param>
    /// <returns>Dictionary mapping entity IDs to their <see cref="EntityLastModifiedData"/> objects.</returns>
    public async Task<Dictionary<int, EntityLastModifiedData>> GetLastModifiedByIdAsync(List<int> entityIds)
    {
        var startTimestamp = Stopwatch.GetTimestamp();
        int? responseCount = null;
        try
        {
            var parameter = CreateTableValuedParameter(entityIds);
            var results = await _dbContext.Database
                .SqlQueryRaw<EntityLastModifiedData>(SqlRawCommand + " " + _sqlCommandParameterName, parameter)
                .ToListAsync();

            var result = new Dictionary<int, EntityLastModifiedData>(results.Count);
            foreach (var item in results)
            {
                result[item.Id] = item;
            }

            responseCount = result.Count;
            return result;
        }
        finally
        {
            var elapsedMs = CommonHelpers.GetElapsedMilliseconds(startTimestamp);
            _logger.LogDebug(
                "Audit query completed: {Command} | Status: {Status} | Duration: {ElapsedMs}ms | Results: {Count} | RequestedIds: {IdCount}",
                SqlRawCommand,
                responseCount.HasValue ? "Success" : "Failure",
                elapsedMs,
                responseCount ?? -1,
                entityIds.Count);
        }
    }

    /// <summary>
    /// Gets the last modified data for a specific entity.
    /// </summary>
    /// <param name="entityId">The entity ID.</param>
    /// <returns><see cref="EntityLastModifiedData"/> if found; otherwise <c>null</c>.</returns>
    public async Task<EntityLastModifiedData?> GetLastModifiedByIdAsync(int entityId)
    {
        var result = await GetLastModifiedByIdAsync([entityId]);
        return result.GetValueOrDefault(entityId);
    }

    private static SqlParameter CreateTableValuedParameter(List<int> ids)
    {
        var dataTable = new DataTable();
        dataTable.Columns.Add("Id", typeof(int));
        dataTable.BeginLoadData();

        foreach (var id in ids)
        {
            dataTable.LoadDataRow([id], true);
        }

        dataTable.EndLoadData();

        return new SqlParameter(_sqlCommandParameterName, SqlDbType.Structured)
        {
            TypeName = _sqlIntIdListTypeName,
            Value = dataTable
        };
    }
}
