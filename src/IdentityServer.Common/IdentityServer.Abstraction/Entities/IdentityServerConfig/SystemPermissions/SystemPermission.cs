// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

using IdentityServer.Abstraction.Contracts;

namespace IdentityServer.Abstraction.Entities.IdentityServerConfig.SystemPermissions;

public class SystemPermission : IHasId<int>, IHasCreatedInfo, IHasUpdatedInfo, IHasPeriodData
{
    public int Id { get; set; }
    public required string Name { get; set; }
    public required string Description { get; set; }
    public DateTime? Updated { get; set; }
    public DateTime Created { get; set; }
    public string? CreatedBy { get; set; }
    public string? UpdatedBy { get; set; }
    public DateTime ValidFrom { get; set; }
    public DateTime ValidTo { get; set; }
    public List<SystemPermissionEnvironment> Environments { get; set; } = new();

    DateTime? IHasCreatedInfo.Created
    {
        get => Created;
        set => Created = value ?? DateTime.UtcNow;
    }

    public override string ToString()
    {
        return $"Permission '{Id}'";
    }
}
