// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

using IdentityServer.Abstraction.DTO.History;
using IdentityServer.Abstraction.Enums;

namespace IdentityServer.AdminPortal.Web.Services.History;

/// <summary>
/// Base class providing common undo functionality for entity-specific services.
/// </summary>
public abstract class EntityHistoryUndoServiceBase
{
    /// <summary>
    /// Entity types that represent secrets and should not be undone.
    /// </summary>
    protected static readonly HashSet<string> SecretEntityTypes = new(StringComparer.OrdinalIgnoreCase)
    {
        HistoryEntryDtoExtensions.KnownEntityTypes.ClientSecret,
        HistoryEntryDtoExtensions.KnownEntityTypes.ApiResourceSecret,
    };

    /// <summary>
    /// Entity types that are parent entities (cannot undo their deletion).
    /// </summary>
    protected static readonly HashSet<string> ParentEntityTypes = new(StringComparer.OrdinalIgnoreCase)
    {
        HistoryEntryDtoExtensions.KnownEntityTypes.Client,
        HistoryEntryDtoExtensions.KnownEntityTypes.ApiResource,
        HistoryEntryDtoExtensions.KnownEntityTypes.SystemPermission
    };

    /// <summary>
    /// Checks base eligibility rules common to all entity types.
    /// </summary>
    protected static UndoEligibility CheckBaseEligibility(HistoryEntryDto entry)
    {
        // Cannot undo Created events
        if (entry.EventType == HistoryEventType.Created)
        {
            return UndoEligibility.Ineligible("Created events cannot be undone. Use the Delete functionality instead.");
        }

        // Cannot undo secret entity operations
        if (IsSecretEntityType(entry.EntityType))
        {
            return UndoEligibility.Ineligible("Secret operations cannot be undone for security reasons.");
        }

        // Cannot undo parent entity deletions (they are not supported via history)
        if (entry.EventType == HistoryEventType.Deleted && ParentEntityTypes.Contains(entry.EntityType))
        {
            return UndoEligibility.Ineligible("Parent entity deletions cannot be undone from history.");
        }

        return UndoEligibility.Eligible();
    }

    /// <summary>
    /// Determines if the entity type is a secret type.
    /// </summary>
    protected static bool IsSecretEntityType(string entityType) =>
        SecretEntityTypes.Contains(entityType);

    /// <summary>
    /// Gets the primary identifying value from a history entry's changes.
    /// </summary>
    protected static string? GetPrimaryValueFromChanges(HistoryEntryDto entry, string primaryField)
    {
        var change = entry.Changes.FirstOrDefault(c => c.FieldName.Equals(primaryField, StringComparison.OrdinalIgnoreCase));
        return change?.OldValue ?? change?.NewValue;
    }

    /// <summary>
    /// Extracts old values from changes, excluding secret fields.
    /// </summary>
    protected static Dictionary<string, string?> GetOldValuesFromChanges(HistoryEntryDto entry)
    {
        return entry.Changes
            .ToDictionary(c => c.FieldName, c => c.OldValue, StringComparer.OrdinalIgnoreCase);
    }

    protected static bool TryGetEntityIdentifierFirstPart(HistoryEntryDto entry, out string firstPart)
    {
        firstPart = string.Empty;

        // Extract the first part from EntityIdentifier format: "{RoleName}:{Value}" or "{SystemPermissionEnvironment}:{User}"
        if (string.IsNullOrEmpty(entry.EntityIdentifier))
        {
            return false;
        }

        if (!TrySplitEntityIdentifierByColon(entry, out firstPart))
        {
            return false;
        }

        return true;
    }

    protected static bool TrySplitEntityIdentifierByColon(HistoryEntryDto entry, out string roleName)
    {
        roleName = string.Empty;
        var colonIndex = entry.EntityIdentifier?.IndexOf(':') ?? -1;
        if (colonIndex < 0)
        {
            return false;
        }
        roleName = entry.EntityIdentifier![..colonIndex];
        return true;
    }
}
