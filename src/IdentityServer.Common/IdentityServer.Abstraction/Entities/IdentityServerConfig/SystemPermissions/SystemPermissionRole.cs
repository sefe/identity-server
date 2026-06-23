// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

using IdentityServer.Abstraction.Attributes;
using IdentityServer.Abstraction.Contracts;

namespace IdentityServer.Abstraction.Entities.IdentityServerConfig.SystemPermissions;

public class SystemPermissionRole : IHasId<int>, IHasCreatedInfo, IHasUpdatedInfo, IHasPeriodData
{
    public int Id { get; set; }
    [HistoryDisplayName("User ID")]
    public required string OId { get; set; }
    public required string Name { get; set; }
    public int SystemPermissionEnvironmentId { get; set; }
    public SystemPermissionRoleType RoleType { get; set; }
    public DateTime? Created { get; set; }
    public string? CreatedBy { get; set; }
    public DateTime? Updated { get; set; }
    public string? UpdatedBy { get; set; }
    public DateTime ValidFrom { get; set; }
    public DateTime ValidTo { get; set; }

    public override string ToString()
    {
        return $"System Permission Role '{Id}'";
    }
}
