// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

using System.Text.Json.Serialization;
using IdentityServer.Abstraction.Contracts;
using IdentityServer.Abstraction.Entities.IdentityServerConfig.SystemPermissions;

namespace IdentityServer.Abstraction.DTO.Clients;

public class ClientShortDtoRead : IDtoRead, IHasEnvironment, IHasCreatedInfo, IHasUpdatedInfo
{
    public int Id { get; set; }
    public required string ClientId { get; set; }
    public required string ClientName { get; set; }
    public int SystemPermissionId { get; set; }
    public string SystemPermissionName { get; set; } = string.Empty;
    public int SystemPermissionEnvironmentId { get; set; }
    public string SystemPermissionEnvironmentName { get; set; } = string.Empty;
    public List<string> SystemPermissionEnvironmentOwnersList { get; set; } = new List<string>();
    [JsonIgnore]
    public string SystemPermissionEnvironmentOwners { get => string.Join(", ", SystemPermissionEnvironmentOwnersList); }
    public SystemPermissionRoleType AccessLevel { get; set; }
    public DateTime? Created { get; set; }
    public string? CreatedBy { get; set; }
    public DateTime? Updated { get; set; }
    public string? UpdatedBy { get; set; }
}
