using System.Diagnostics;
using System.Security.Claims;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Logging;
using IdentityServer.Abstraction.Contracts;
using IdentityServer.Abstraction.DTO.History;
using IdentityServer.Abstraction.Exceptions;
using IdentityServer.Abstraction.Extensions;
using IdentityServer.Data.DbContexts;
using IdentityServer.Data.DuendeEntityExtensions;
using IdentityServer.Data.Entities.Roles;
using IdentityServer.Data.Services;

namespace IdentityServer.Data.Repositories.DtoRepositories.ApiResource;

/// <summary>
/// Repository for querying API resource change history from temporal tables.
/// </summary>
internal class ApiResourceHistoryDtoRepository : BaseHistoryRepository, IApiResourceHistoryRepository
{
    protected override string ParentIdPropertyName => "ApiResourceId";
    private readonly IHistoryService _historyService;

    private static string[] GetApiResourceFieldsToCompare() => new[]
    {
        nameof(ApiResourceExt.Name),
        nameof(ApiResourceExt.DisplayName),
        nameof(ApiResourceExt.Description),
        nameof(ApiResourceExt.Enabled),
        nameof(ApiResourceExt.SystemPermissionEnvironmentId)
    };

    private static string[] GetApiScopeFieldsToCompare() => new[]
{
        nameof(ApiScopeExt.Name),
        nameof(ApiScopeExt.DisplayName),
        nameof(ApiScopeExt.Description),
        nameof(ApiScopeExt.Enabled),
        nameof(ApiScopeExt.Required)
    };

    public ApiResourceHistoryDtoRepository(
        IDbContextFactory<IdentityServerConfigurationDbContext> contextFactory,
        IPermissionChecker permissionChecker,
        ILogger<ApiResourceHistoryDtoRepository> logger,
        IHistoryService historyService)
        : base(contextFactory, permissionChecker, logger, historyService)
    {
        _historyService = historyService;
    }

    /// <summary>
    /// Gets the complete change history for an API resource and all its nested entities.
    /// </summary>
    /// <param name="user">The user requesting the history.</param>
    /// <param name="entityId">The database ID of the Api Resource entity.</param>
    /// <returns>A complete history response including all events.</returns>
    public async Task<HistoryResponseDto> GetHistoryAsync(ClaimsPrincipal user, int entityId)
    {
        var ts = Stopwatch.GetTimestamp();

        // Get main API resource history first to validate existence and extract current state
        var (mainHistoryEvents, currentApiResource) = await GetApiResourceMainHistoryWithEntityAsync(entityId);
        if (currentApiResource == null || currentApiResource.ValidTo < DateTime.MaxValue)
        {
            throw new EntityNotFoundException($"API Resource with ID '{entityId}' not found.");
        }

        // Check permissions - same as reading the API resource
        await _permissionChecker.GetAccessRoleOrThrowIfNoAccessToEnvAsync(
            user,
            currentApiResource.SystemPermissionEnvironmentId,
            EntityAccessType.Read,
            currentApiResource.ToString()!);

        // Execute remaining history queries in parallel using separate DbContext instances
        var sortedEvents = await ExecuteHistoryQueriesAndMergeAsync(
            Task.FromResult(mainHistoryEvents),
            GetApiResourceRolesHistoryAsync(entityId),
            GetApiResourceRoleMappingsHistoryAsync(entityId),
            GetApiResourceSecretsHistoryAsync(entityId),
            GetApiScopeHistoryAsync(entityId));

        LogHistoryRetrieval("API resource", entityId, user, ts, sortedEvents.Count);

        return CreateHistoryResponse(entityId, currentApiResource.Name, sortedEvents);
    }

    private async Task<(List<HistoryEntryDto> Events, ApiResourceExt? LatestVersion)> GetApiResourceMainHistoryWithEntityAsync(int apiResourceId)
    {
        await using var context = await _contextFactory.CreateDbContextAsync();

        var allVersions = await context.ApiResources
            .TemporalAll()
            .Where(a => a.Id == apiResourceId)
            .OrderBy(a => a.ValidFrom)
            .ToListAsync();

        if (allVersions.Count == 0)
        {
            return (new List<HistoryEntryDto>(), null);
        }

        var fieldsToCompare = GetApiResourceFieldsToCompare();
        var events = _historyService.TrackVersionChanges(
            allVersions,
            fieldsToCompare,
            a => a.Name);

        var latestVersion = allVersions[^1];

        return (events, latestVersion);
    }

    private async Task<List<HistoryEntryDto>> GetApiResourceRoleMappingsHistoryAsync(int apiResourceId)
    {
        await using var context = await _contextFactory.CreateDbContextAsync();

        var roleNameLookup = await GetRoleNameLookupAsync(context, apiResourceId);
        if (roleNameLookup.Count == 0)
        {
            return new List<HistoryEntryDto>();
        }

        var roleIds = roleNameLookup.Keys.ToList();
        var allVersions = await context.RoleMappings
            .TemporalAll()
            .Where(rm => roleIds.Contains(rm.ApiResourceRoleId))
            .ToListAsync();

        return _historyService.ProcessRoleMappingVersions(
            allVersions,
            roleNameLookup,
            rm => rm.ApiResourceRoleId,
            rm => rm.MappingType.ToString(),
            rm => rm.Value,
            rm => rm.Description);
    }

    private static async Task<Dictionary<int, string>> GetRoleNameLookupAsync(
        IdentityServerConfigurationDbContext context,
        int apiResourceId)
    {
        return await context.ApiResourceRoles
            .TemporalAll()
            .Where(r => r.ApiResourceId == apiResourceId)
            .GroupBy(r => r.Id)
            .Select(g => g.First())
            .ToDictionaryAsync(r => r.Id, r => r.RoleName);
    }

    private Task<List<HistoryEntryDto>> GetApiResourceRolesHistoryAsync(int apiResourceId) =>
        GetAddRemoveEntityHistoryAsync<ApiResourceRole>(
            apiResourceId,
            r => r.RoleName,
            r => new() { new FieldChangeDto(nameof(ApiResourceRole.RoleName), r.RoleName) });

    private Task<List<HistoryEntryDto>> GetApiResourceSecretsHistoryAsync(int apiResourceId) =>
        GetAddRemoveEntityHistoryAsync<ApiResourceSecretExt>(
            apiResourceId,
            s => s.Description,
            s => new()
            {
                new FieldChangeDto(nameof(ApiResourceSecretExt.Description), s.Description),
                new FieldChangeDto(nameof(ApiResourceSecretExt.Preview), s.Preview.FormatAsSecretPreview())
            });

    /// <summary>
    /// Get history for ApiScope entities that are linked to the API resource.
    /// ApiScope has field updates (DisplayName, Description, Enabled, Required) unlike other child entities.
    /// </summary>
    private async Task<List<HistoryEntryDto>> GetApiScopeHistoryAsync(int apiResourceId)
    {
        await using var context = await _contextFactory.CreateDbContextAsync();

        // Get all scope names associated with this API resource from ApiResourceScopes
        var scopeNames = await context.ApiResourceScopes
            .TemporalAll()
            .Where(s => s.ApiResourceId == apiResourceId)
            .Select(s => s.Scope)
            .Distinct()
            .ToListAsync();

        if (scopeNames.Count == 0)
        {
            return new List<HistoryEntryDto>();
        }

        // Get all versions of ApiScope entities for these scope names
        var allVersions = await context.ApiScopes
            .TemporalAll()
            .Where(s => scopeNames.Contains(s.Name))
            .ToListAsync();

        return ProcessApiScopeVersions(allVersions);
    }

    private List<HistoryEntryDto> ProcessApiScopeVersions(List<ApiScopeExt> allVersions)
    {
        var events = new List<HistoryEntryDto>();
        var groupedById = allVersions.GroupBy(v => v.Id);

        var fieldsToCompare = GetApiScopeFieldsToCompare();
        foreach (var scopeVersions in groupedById)
        {
            var orderedVersions = scopeVersions.OrderBy(v => v.ValidFrom).ToList();
            events.AddRange(_historyService.TrackVersionChanges(
                orderedVersions,
                fieldsToCompare,
                s => s.Name,
                true));
        }

        return events;
    }
}
