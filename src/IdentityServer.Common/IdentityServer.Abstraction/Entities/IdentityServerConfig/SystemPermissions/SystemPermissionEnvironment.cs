// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

using IdentityServer.Abstraction.Contracts;

namespace IdentityServer.Abstraction.Entities.IdentityServerConfig.SystemPermissions;

public class SystemPermissionEnvironment : IHasId<int>, IHasCreatedInfo, IHasUpdatedInfo, IHasPeriodData
{
    public int Id { get; set; }
    public required string Environment { get; set; }
    public int SystemPermissionId { get; set; }
    public required SystemPermission SystemPermission { get; set; }
    public List<SystemPermissionRole> Permissions { get; set; } = new();
    public DateTime? Created { get; set; }
    public string? CreatedBy { get; set; }
    public DateTime? Updated { get; set; }
    public string? UpdatedBy { get; set; }
    public DateTime ValidFrom { get; set; }
    public DateTime ValidTo { get; set; }

    public string GetOwners()
    {
        return string.Join(", ", GetOwnersList());
    }
    public List<string> GetOwnersList()
    {
        return Permissions.Where(_ => _.RoleType == SystemPermissionRoleType.Writer)
                          .Select(_ => _.Name).OrderBy(_ => _).ToList();
    }
}
