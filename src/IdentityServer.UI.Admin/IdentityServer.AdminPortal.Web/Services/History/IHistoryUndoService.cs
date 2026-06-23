// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

using IdentityServer.Abstraction.DTO.ApiResources;
using IdentityServer.Abstraction.DTO.Clients;
using IdentityServer.Abstraction.DTO.History;
using IdentityServer.Abstraction.DTO.SystemPermissions;

namespace IdentityServer.AdminPortal.Web.Services.History;

/// <summary>
/// Service for determining undo eligibility and executing undo operations on history entries.
/// </summary>
public interface IHistoryUndoService
{
    /// <summary>
    /// Determines whether a history entry can be undone and provides the reason if not.
    /// </summary>
    /// <param name="entry">The history entry to evaluate.</param>
    /// <param name="currentClient">The current state of the client entity (for conflict detection).</param>
    /// <returns>The undo eligibility result.</returns>
    UndoEligibility CanUndo(HistoryEntryDto entry, ClientDtoRead? currentClient);

    /// <summary>
    /// Determines whether a history entry can be undone and provides the reason if not.
    /// </summary>
    /// <param name="entry">The history entry to evaluate.</param>
    /// <param name="currentApiResource">The current state of the API resource entity (for conflict detection).</param>
    /// <returns>The undo eligibility result.</returns>
    UndoEligibility CanUndo(HistoryEntryDto entry, ApiResourceDtoRead? currentApiResource);

    /// <summary>
    /// Determines whether a history entry can be undone and provides the reason if not.
    /// </summary>
    /// <param name="entry">The history entry to evaluate.</param>
    /// <param name="currentSystemPermission">The current state of the system permission entity (for conflict detection).</param>
    /// <returns>The undo eligibility result.</returns>
    UndoEligibility CanUndo(HistoryEntryDto entry, SystemPermissionDtoRead? currentSystemPermission);

    /// <summary>
    /// Gets a preview of the changes that will be reversed by an undo operation.
    /// </summary>
    /// <param name="entry">The history entry to preview.</param>
    /// <returns>The undo preview with field changes that will be reversed.</returns>
    UndoPreview GetUndoPreview(HistoryEntryDto entry);

    /// <summary>
    /// Executes the undo operation for a client-related history entry.
    /// </summary>
    /// <param name="entry">The history entry to undo.</param>
    /// <param name="currentClient">The current state of the client entity.</param>
    /// 
    /// <returns>The result containing the updated client entity.</returns>
    Task<ApiCallResult<ClientDtoRead>> ExecuteUndoAsync(HistoryEntryDto entry, ClientDtoRead currentClient);

    /// <summary>
    /// Executes the undo operation for an API resource-related history entry.
    /// </summary>
    /// <param name="entry">The history entry to undo.</param>
    /// <param name="currentApiResource">The current state of the API resource entity.</param>
    /// 
    /// <returns>The result containing the updated API resource entity.</returns>
    Task<ApiCallResult<ApiResourceDtoRead>> ExecuteUndoAsync(HistoryEntryDto entry, ApiResourceDtoRead currentApiResource);

    /// <summary>
    /// Executes the undo operation for a system permission-related history entry.
    /// </summary>
    /// <param name="entry">The history entry to undo.</param>
    /// <param name="currentSystemPermission">The current state of the system permission entity.</param>
    /// 
    /// <returns>The result containing the updated system permission entity.</returns>
    Task<ApiCallResult<SystemPermissionDtoRead>> ExecuteUndoAsync(HistoryEntryDto entry, SystemPermissionDtoRead currentSystemPermission);
}

/// <summary>
/// Represents the result of an undo eligibility check.
/// </summary>
public class UndoEligibility
{
    /// <summary>
    /// Gets a value indicating whether the undo operation can be performed.
    /// </summary>
    public bool CanUndo { get; init; }

    /// <summary>
    /// Gets the reason why the undo operation cannot be performed, if applicable.
    /// </summary>
    public string? Reason { get; init; }

    /// <summary>
    /// Creates a successful eligibility result.
    /// </summary>
    public static UndoEligibility Eligible() => new() { CanUndo = true };

    /// <summary>
    /// Creates an ineligible result with the specified reason.
    /// </summary>
    public static UndoEligibility Ineligible(string reason) => new() { CanUndo = false, Reason = reason };
}

/// <summary>
/// Represents a preview of the undo operation.
/// </summary>
public class UndoPreview
{
    /// <summary>
    /// Gets the list of field changes that will be reversed.
    /// </summary>
    public List<FieldChangeDto> ChangesToReverse { get; init; } = new();
}
