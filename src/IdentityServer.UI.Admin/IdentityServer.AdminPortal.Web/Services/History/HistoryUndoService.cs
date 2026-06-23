// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

using IdentityServer.Abstraction.DTO.ApiResources;
using IdentityServer.Abstraction.DTO.Clients;
using IdentityServer.Abstraction.DTO.History;
using IdentityServer.Abstraction.DTO.SystemPermissions;

namespace IdentityServer.AdminPortal.Web.Services.History;

/// <summary>
/// Coordinator service for determining undo eligibility and executing undo operations on history entries.
/// Delegates to entity-specific services for actual undo logic.
/// </summary>
public class HistoryUndoService : IHistoryUndoService
{
    private readonly IEntityHistoryUndoService<ClientDtoRead> _clientUndoService;
    private readonly IEntityHistoryUndoService<ApiResourceDtoRead> _apiResourceUndoService;
    private readonly IEntityHistoryUndoService<SystemPermissionDtoRead> _systemPermissionUndoService;

    public HistoryUndoService(
        IEntityHistoryUndoService<ClientDtoRead> clientUndoService,
        IEntityHistoryUndoService<ApiResourceDtoRead> apiResourceUndoService,
        IEntityHistoryUndoService<SystemPermissionDtoRead> systemPermissionUndoService)
    {
        _clientUndoService = clientUndoService;
        _apiResourceUndoService = apiResourceUndoService;
        _systemPermissionUndoService = systemPermissionUndoService;
    }

    /// <inheritdoc />
    public UndoEligibility CanUndo(HistoryEntryDto entry, ClientDtoRead? currentClient)
    {
        return _clientUndoService.CanUndo(entry, currentClient);
    }

    /// <inheritdoc />
    public UndoEligibility CanUndo(HistoryEntryDto entry, ApiResourceDtoRead? currentApiResource)
    {
        return _apiResourceUndoService.CanUndo(entry, currentApiResource);
    }

    /// <inheritdoc />
    public UndoEligibility CanUndo(HistoryEntryDto entry, SystemPermissionDtoRead? currentSystemPermission)
    {
        return _systemPermissionUndoService.CanUndo(entry, currentSystemPermission);
    }

    /// <inheritdoc />
    public UndoPreview GetUndoPreview(HistoryEntryDto entry)
    {
        var changesToReverse = new List<FieldChangeDto>();

        foreach (var change in entry.Changes)
        {
            // Create reversed change (swap old and new values)
            var reversedChange = new FieldChangeDto
            {
                FieldName = change.FieldName,
                OldValue = change.NewValue,
                NewValue = change.OldValue
            };
            changesToReverse.Add(reversedChange);
        }

        return new UndoPreview
        {
            ChangesToReverse = changesToReverse,
        };
    }

    /// <inheritdoc />
    public async Task<ApiCallResult<ClientDtoRead>> ExecuteUndoAsync(HistoryEntryDto entry, ClientDtoRead currentClient)
    {
        if (!_clientUndoService.CanHandle(entry.EntityType))
        {
            return ApiCallResult<ClientDtoRead>.Error($"Client undo handler doesn't support entity type: {entry.EntityType}");
        }

        return await _clientUndoService.ExecuteUndoAsync(entry, currentClient);
    }

    /// <inheritdoc />
    public async Task<ApiCallResult<ApiResourceDtoRead>> ExecuteUndoAsync(HistoryEntryDto entry, ApiResourceDtoRead currentApiResource)
    {
        if (!_apiResourceUndoService.CanHandle(entry.EntityType))
        {
            return ApiCallResult<ApiResourceDtoRead>.Error($"API Resource undo handler doesn't support entity type: {entry.EntityType}");
        }

        return await _apiResourceUndoService.ExecuteUndoAsync(entry, currentApiResource);
    }

    /// <inheritdoc />
    public async Task<ApiCallResult<SystemPermissionDtoRead>> ExecuteUndoAsync(HistoryEntryDto entry, SystemPermissionDtoRead currentSystemPermission)
    {
        if (!_systemPermissionUndoService.CanHandle(entry.EntityType))
        {
            return ApiCallResult<SystemPermissionDtoRead>.Error($"System Permission undo handler doesn't support entity type: {entry.EntityType}");
        }

        return await _systemPermissionUndoService.ExecuteUndoAsync(entry, currentSystemPermission);
    }
}
