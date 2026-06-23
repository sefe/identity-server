// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

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

namespace IdentityServer.Data.Repositories.DtoRepositories.Client;

/// <summary>
/// Repository for querying client change history from temporal tables.
/// </summary>
internal class ClientHistoryDtoRepository : BaseHistoryRepository, IClientHistoryRepository
{
    protected override string ParentIdPropertyName => "ClientId";
    private readonly IHistoryService _historyService;

    private static string[] GetClientFieldsToCompare() => new[]
    {
        nameof(ClientExt.ClientId),
        nameof(ClientExt.ClientName),
        nameof(ClientExt.Description),
        nameof(ClientExt.Enabled),
        nameof(ClientExt.RequireClientSecret),
        nameof(ClientExt.RequirePkce),
        nameof(ClientExt.AllowPlainTextPkce),
        nameof(ClientExt.AllowOfflineAccess),
        nameof(ClientExt.AllowAccessTokensViaBrowser),
        nameof(ClientExt.RefreshTokenUsage),
        nameof(ClientExt.RefreshTokenExpiration),
        nameof(ClientExt.UpdateAccessTokenClaimsOnRefresh),
        nameof(ClientExt.AlwaysIncludeUserClaimsInIdToken),
        nameof(ClientExt.AlwaysSendClientClaims),
        nameof(ClientExt.ClientClaimsPrefix),
        nameof(ClientExt.SystemPermissionEnvironmentId)
    };

    public ClientHistoryDtoRepository(
        IDbContextFactory<IdentityServerConfigurationDbContext> contextFactory,
        IPermissionChecker permissionChecker,
        ILogger<ClientHistoryDtoRepository> logger,
        IHistoryService historyService)
        : base(contextFactory, permissionChecker, logger, historyService)
    {
        _historyService = historyService;
    }

    /// <summary>
    /// Gets the complete change history for a Client entity and all its nested entities.
    /// </summary>
    /// <param name="user">The user requesting the history.</param>
    /// <param name="entityId">The database ID of the Client entity.</param>
    /// <returns>A complete history response including all events.</returns>
    public async Task<HistoryResponseDto> GetHistoryAsync(ClaimsPrincipal user, int entityId)
    {
        var ts = Stopwatch.GetTimestamp();

        // Get main client history first to validate existence and extract current state
        var (mainHistoryEvents, currentClient) = await GetClientMainHistoryWithEntityAsync(entityId);

        // Validate that the client exists (has history entries and is not deleted)
        if (currentClient == null || currentClient.ValidTo < DateTime.MaxValue)
        {
            throw new EntityNotFoundException($"Client with ID '{entityId}' not found.");
        }

        // Check permissions - same as reading the client
        await _permissionChecker.GetAccessRoleOrThrowIfNoAccessToEnvAsync(
            user,
            currentClient.SystemPermissionEnvironmentId,
            EntityAccessType.Read,
            currentClient.ToString()!);

        // Execute remaining history queries in parallel using separate DbContext instances
        var sortedEvents = await ExecuteHistoryQueriesAndMergeAsync(
            Task.FromResult(mainHistoryEvents),
            GetClientRolesHistoryAsync(entityId),
            GetClientRoleMappingsHistoryAsync(entityId),
            GetClientSecretsHistoryAsync(entityId),
            GetClientScopesHistoryAsync(entityId),
            GetClientRedirectsHistoryAsync(entityId),
            GetClientPostLogoutRedirectsHistoryAsync(entityId),
            GetClientGrantsHistoryAsync(entityId),
            GetClientCorsOriginsHistoryAsync(entityId),
            GetClientEntraAppsHistoryAsync(entityId));

        LogHistoryRetrieval("client", entityId, user, ts, sortedEvents.Count);

        return CreateHistoryResponse(entityId, currentClient.ClientName ?? currentClient.ClientId, sortedEvents);
    }

    private async Task<(List<HistoryEntryDto> Events, ClientExt? LatestVersion)> GetClientMainHistoryWithEntityAsync(int clientId)
    {
        await using var context = await _contextFactory.CreateDbContextAsync();

        var allVersions = await context.Clients
            .TemporalAll()
            .Where(c => c.Id == clientId)
            .OrderBy(c => c.ValidFrom)
            .ToListAsync();

        if (allVersions.Count == 0)
        {
            return (new List<HistoryEntryDto>(), null);
        }

        var fieldsToCompare = GetClientFieldsToCompare();
        var events = _historyService.TrackVersionChanges(
            allVersions,
            fieldsToCompare,
            client => client.ClientId);

        var latestVersion = allVersions[^1];

        return (events, latestVersion);
    }

    private async Task<List<HistoryEntryDto>> GetClientRoleMappingsHistoryAsync(int clientId)
    {
        await using var context = await _contextFactory.CreateDbContextAsync();

        var roleNameLookup = await GetRoleNameLookupAsync(context, clientId);
        if (roleNameLookup.Count == 0)
        {
            return new List<HistoryEntryDto>();
        }

        var roleIds = roleNameLookup.Keys.ToList();
        var allVersions = await context.Set<ClientRoleMapping>()
            .TemporalAll()
            .Where(m => roleIds.Contains(m.ClientRoleId))
            .ToListAsync();

        return _historyService.ProcessRoleMappingVersions(
            allVersions,
            roleNameLookup,
            m => m.ClientRoleId,
            m => m.MappingType.ToString(),
            m => m.Value,
            m => m.Description);
    }

    private static async Task<Dictionary<int, string>> GetRoleNameLookupAsync(
        IdentityServerConfigurationDbContext context,
        int clientId)
    {
        return await context.ClientRoles
            .TemporalAll()
            .Where(r => r.ClientId == clientId)
            .GroupBy(r => r.Id)
            .Select(g => g.First())
            .ToDictionaryAsync(r => r.Id, r => r.RoleName);
    }

    private Task<List<HistoryEntryDto>> GetClientRolesHistoryAsync(int clientId) =>
        GetAddRemoveEntityHistoryAsync<ClientRole>(
            clientId,
            r => r.RoleName,
            r => new() { new FieldChangeDto(nameof(ClientRole.RoleName), r.RoleName) });

    private Task<List<HistoryEntryDto>> GetClientGrantsHistoryAsync(int clientId) =>
        GetAddRemoveEntityHistoryAsync<ClientGrantTypeExt>(
            clientId,
            g => g.GrantType,
            g => new() { new FieldChangeDto(nameof(ClientGrantTypeExt.GrantType), g.GrantType) });

    private Task<List<HistoryEntryDto>> GetClientScopesHistoryAsync(int clientId) =>
        GetAddRemoveEntityHistoryAsync<ClientScopeExt>(
            clientId,
            s => s.Scope,
            s => new() { new FieldChangeDto(nameof(ClientScopeExt.Scope), s.Scope) });

    private Task<List<HistoryEntryDto>> GetClientRedirectsHistoryAsync(int clientId) =>
        GetAddRemoveEntityHistoryAsync<ClientRedirectUriExt>(
            clientId,
            r => r.RedirectUri,
            r => new() { new FieldChangeDto(nameof(ClientRedirectUriExt.RedirectUri), r.RedirectUri) });

    private Task<List<HistoryEntryDto>> GetClientPostLogoutRedirectsHistoryAsync(int clientId) =>
        GetAddRemoveEntityHistoryAsync<ClientPostLogoutRedirectUriExt>(
            clientId,
            r => r.PostLogoutRedirectUri,
            r => new() { new FieldChangeDto(nameof(ClientPostLogoutRedirectUriExt.PostLogoutRedirectUri), r.PostLogoutRedirectUri) });

    private Task<List<HistoryEntryDto>> GetClientCorsOriginsHistoryAsync(int clientId) =>
        GetAddRemoveEntityHistoryAsync<ClientCorsOriginExt>(
            clientId,
            c => c.Origin,
            c => new() { new FieldChangeDto(nameof(ClientCorsOriginExt.Origin), c.Origin) });

    private Task<List<HistoryEntryDto>> GetClientSecretsHistoryAsync(int clientId) =>
        GetAddRemoveEntityHistoryAsync<ClientSecretExt>(
            clientId,
            r => r.Description,
            r => new() {
               new FieldChangeDto(nameof(ClientSecretExt.Description), r.Description),
               new FieldChangeDto(nameof(ClientSecretExt.Preview), r.Preview.FormatAsSecretPreview())
            });

    private Task<List<HistoryEntryDto>> GetClientEntraAppsHistoryAsync(int clientId) =>
        GetAddRemoveEntityHistoryAsync<ClientEntraApp>(
            clientId,
            e => e.AppId,
            e => new()
            {
                new FieldChangeDto(nameof(ClientEntraApp.AppId), e.AppId),
                new FieldChangeDto(nameof(ClientEntraApp.AppName), e.AppName)
            });
}
