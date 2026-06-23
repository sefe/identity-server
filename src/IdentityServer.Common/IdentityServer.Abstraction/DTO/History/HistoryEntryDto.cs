// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

namespace IdentityServer.Abstraction.DTO.History;

using System.ComponentModel.DataAnnotations;
using System.Text.Json.Serialization;
using IdentityServer.Abstraction.Enums;

/// <summary>
/// Represents a single change event in entity history.
/// </summary>
public class HistoryEntryDto
{
    /// <summary>
    /// Gets or sets the timestamp when the change occurred.
    /// </summary>
    public DateTime Timestamp { get; set; }

    /// <summary>
    /// Gets or sets the type of event (Created, Updated, Deleted).
    /// </summary>
    [EnumDataType(typeof(HistoryEventType))]
    public required HistoryEventType EventType { get; set; }

    /// <summary>
    /// Gets or sets the type of entity that changed. Usually the data layer class name (e.g., ClientExt, ApiResourceExt, ApiScopeExt).
    /// </summary>
    public required string EntityType { get; set; }

    [JsonIgnore]
    public string EntityTypeDisplayName => HistoryEntryDtoExtensions.GetDisplayName(EntityType);

    /// <summary>
    /// Gets or sets an identifier for the entity (e.g., ClientId, RoleName, RedirectUri, Permission Name, Environment, Role Name).
    /// </summary>
    public string? EntityIdentifier { get; set; }

    /// <summary>
    /// Gets or sets the user who made the change.
    /// </summary>
    public string? ChangedBy { get; set; }

    /// <summary>
    /// Gets or sets the list of field changes for this event.
    /// </summary>
    public List<FieldChangeDto> Changes { get; set; } = new();
}

public static class HistoryEntryDtoExtensions
{
    public static class KnownEntityTypes
    {
        public const string Client = "ClientExt";
        public const string ClientCorsOrigin = "ClientCorsOriginExt";
        public const string ClientGrantType = "ClientGrantTypeExt";
        public const string ClientScope = "ClientScopeExt";
        public const string ClientRedirectUri = "ClientRedirectUriExt";
        public const string ClientRole = "ClientRole";
        public const string ClientRoleMapping = "ClientRoleMapping";
        public const string ClientPostLogoutRedirectUri = "ClientPostLogoutRedirectUriExt";
        public const string ClientSecret = "ClientSecretExt";
        public const string ClientEntraApp = "ClientEntraApp";

        public const string ApiScope = "ApiScopeExt";
        public const string ApiResource = "ApiResourceExt";
        public const string ApiResourceRole = "ApiResourceRole";
        public const string ApiResourceRoleMapping = "ApiResourceRoleMapping";
        public const string ApiResourceSecret = "ApiResourceSecretExt";

        public const string SystemPermission = "SystemPermission";
        public const string SystemPermissionEnvironment = "SystemPermissionEnvironment";
        public const string SystemPermissionRole = "SystemPermissionRole";
    }

    public static readonly IReadOnlyDictionary<string, string> DisplayNames = new Dictionary<string, string>
    {
        { KnownEntityTypes.Client, "Application"},
        { KnownEntityTypes.ClientCorsOrigin, "CORS Origin"},
        { KnownEntityTypes.ClientEntraApp, "Entra App Reference"},
        { KnownEntityTypes.ClientGrantType, "Grant Type"},
        { KnownEntityTypes.ClientPostLogoutRedirectUri, "Post Logout Redirect URI"},
        { KnownEntityTypes.ClientRedirectUri, "Redirect URI"},
        { KnownEntityTypes.ClientRole, "Role"},
        { KnownEntityTypes.ClientRoleMapping, "Role Mapping"},
        { KnownEntityTypes.ClientSecret, "Secret"},
        { KnownEntityTypes.ClientScope, "Scope Reference"},

        { KnownEntityTypes.ApiScope, "Scope"},
        { KnownEntityTypes.ApiResource, "API Resource"},
        { KnownEntityTypes.ApiResourceRole, "Role"},
        { KnownEntityTypes.ApiResourceRoleMapping, "Role Mapping"},
        { KnownEntityTypes.ApiResourceSecret, "Secret"},

        { KnownEntityTypes.SystemPermission, "SystemPermission"},
        { KnownEntityTypes.SystemPermissionEnvironment, "Environment"},
        { KnownEntityTypes.SystemPermissionRole, "Role"},
    };

    public static string GetDisplayName(string? entityType)
    {
        if (entityType == null)
        {
            return string.Empty;
        }
        return DisplayNames.TryGetValue(entityType, out var displayName)
            ? displayName
            : entityType;
    }
}
