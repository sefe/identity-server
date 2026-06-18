using System.Diagnostics;
using System.Security.Claims;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Logging;
using IdentityServer.Abstraction.Contracts;
using IdentityServer.Abstraction.DTO.History;
using IdentityServer.Abstraction.Entities.IdentityServerConfig.SystemPermissions;
using IdentityServer.Abstraction.Enums;
using IdentityServer.Abstraction.Exceptions;
using IdentityServer.Data.DbContexts;
using IdentityServer.Data.Services;

namespace IdentityServer.Data.Repositories.DtoRepositories.SystemPermissions;

/// <summary>
/// Repository for querying system permission change history from temporal tables.
/// </summary>
internal class SystemPermissionHistoryDtoRepository : BaseHistoryRepository, ISystemPermissionHistoryRepository
{
    protected override string ParentIdPropertyName => "SystemPermissionId";

    private readonly IHistoryService _historyService;

    private static string[] GetSystemPermissionFieldsToCompare() => new[]
    {
        nameof(SystemPermission.Name),
        nameof(SystemPermission.Description)
    };

    private static string[] GetRoleFieldsToCompare() => new[]
    {
        nameof(SystemPermissionRole.Name),
        nameof(SystemPermissionRole.OId),
        nameof(SystemPermissionRole.RoleType)
    };

    public SystemPermissionHistoryDtoRepository(
        IDbContextFactory<IdentityServerConfigurationDbContext> contextFactory,
        IPermissionChecker permissionChecker,
        ILogger<SystemPermissionHistoryDtoRepository> logger,
        IHistoryService historyService)
        : base(contextFactory, permissionChecker, logger, historyService)
    {
        _historyService = historyService;
    }

    /// <summary>
    /// Gets the complete change history for a System Permission entity and all its nested entities.
    /// </summary>
    /// <param name="user">The user requesting the history.</param>
    /// <param name="entityId">The database ID of the System Permission entity.</param>
    /// <returns>A complete history response including all events.</returns>
    public async Task<HistoryResponseDto> GetHistoryAsync(ClaimsPrincipal user, int entityId)
    {
        await using var context = await _contextFactory.CreateDbContextAsync();

        // Get current permission for permission check and basic info
        var currentPermission = await context.SystemPermissions
            .AsNoTracking()
            .Include(p => p.Environments)
                .ThenInclude(e => e.Permissions)
            .FirstOrDefaultAsync(p => p.Id == entityId)
            ?? throw new EntityNotFoundException($"System Permission with ID '{entityId}' not found.");

        // Check permissions - user must have at least read access to the system permission
        _permissionChecker.GetAccessRoleOrThrowIfNoAccessToSystem(
            user,
            currentPermission,
            EntityAccessType.Read,
            currentPermission.ToString()!);

        var ts = Stopwatch.GetTimestamp();

        // Execute all history queries in parallel using separate DbContext instances
        var sortedEvents = await ExecuteHistoryQueriesAndMergeAsync(
            GetSystemPermissionMainHistoryAsync(entityId),
            GetSystemPermissionEnvironmentsHistoryAsync(entityId),
            GetSystemPermissionRolesHistoryAsync(entityId));

        LogHistoryRetrieval("System Permission", entityId, user, ts, sortedEvents.Count);

        return CreateHistoryResponse(entityId, currentPermission.Name, sortedEvents);
    }

    private async Task<List<HistoryEntryDto>> GetSystemPermissionMainHistoryAsync(int systemPermissionId)
    {
        await using var context = await _contextFactory.CreateDbContextAsync();

        var allVersions = await context.SystemPermissions
            .TemporalAll()
            .Where(p => p.Id == systemPermissionId)
            .OrderBy(p => p.ValidFrom)
            .ToListAsync();

        var fieldsToCompare = GetSystemPermissionFieldsToCompare();
        var events = _historyService.TrackVersionChanges(
            allVersions,
            fieldsToCompare,
            p => p.Name);

        return events;
    }

    private async Task<List<HistoryEntryDto>> GetSystemPermissionEnvironmentsHistoryAsync(int systemPermissionId)
    {
        await using var context = await _contextFactory.CreateDbContextAsync();

        var allVersions = await context.SystemPermissionEnvironments
            .TemporalAll()
            .Where(e => e.SystemPermissionId == systemPermissionId)
            .ToListAsync();

        return _historyService.ProcessAddRemoveEntityVersions(
            allVersions,
            e => e.Environment,
            e => new() { new FieldChangeDto(nameof(SystemPermissionEnvironment.Environment), e.Environment, HistoryEventType.Created) });
    }

    private async Task<List<HistoryEntryDto>> GetSystemPermissionRolesHistoryAsync(int systemPermissionId)
    {
        await using var context = await _contextFactory.CreateDbContextAsync();

        var environmentIds = await context.SystemPermissionEnvironments
            .TemporalAll()
            .Where(e => e.SystemPermissionId == systemPermissionId)
            .Select(e => e.Id)
            .Distinct()
            .ToListAsync();

        var allRoleVersions = await context.SystemPermissionRole
            .TemporalAll()
            .Where(r => environmentIds.Contains(r.SystemPermissionEnvironmentId))
            .OrderBy(r => r.ValidFrom)
            .ToListAsync();

        var environmentNameLookup = await GetEnvironmentNameLookupAsync(context, systemPermissionId);

        return ProcessRoleVersions(allRoleVersions, environmentNameLookup);
    }

    private static async Task<Dictionary<int, string>> GetEnvironmentNameLookupAsync(IdentityServerConfigurationDbContext context, int systemPermissionId)
    {
        return await context.SystemPermissionEnvironments
            .TemporalAll()
            .Where(e => e.SystemPermissionId == systemPermissionId)
            .GroupBy(e => e.Id)
            .Select(g => g.First())
            .ToDictionaryAsync(e => e.Id, e => e.Environment);
    }

    private List<HistoryEntryDto> ProcessRoleVersions(List<SystemPermissionRole> allVersions, Dictionary<int, string> environmentNameLookup)
    {
        var events = new List<HistoryEntryDto>();
        var groupedById = allVersions.GroupBy(v => v.Id);

        var fieldsToCompare = GetRoleFieldsToCompare();

        foreach (var roleVersions in groupedById)
        {
            var orderedVersions = roleVersions.OrderBy(r => r.ValidFrom).ToList();

            var firstVersion = orderedVersions[0];
            var environmentName = environmentNameLookup[firstVersion.SystemPermissionEnvironmentId];
            var changes = _historyService.TrackVersionChanges(orderedVersions, fieldsToCompare, role => $"{environmentName}:{role.Name}", true);
            events.AddRange(changes);
        }

        return events;
    }
}
