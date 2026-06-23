// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

using IdentityServer.Abstraction.Contracts;
using IdentityServer.Data.DuendeEntityExtensions;

namespace IdentityServer.Data.Entities.Roles;

public class ApiResourceRole : IHasCreatedInfo, IHasUpdatedInfo, IHasPeriodData, IHasId<int>
{
    public int Id { get; set; }
    public int ApiResourceId { get; set; }
    public required string RoleName { get; set; }
    public DateTime Created { get; set; }
    DateTime? IHasCreatedInfo.Created
    {
        get => Created;
        set => Created = value ?? DateTime.UtcNow;
    }
    public string? CreatedBy { get; set; }
    public DateTime? Updated { get; set; }
    public string? UpdatedBy { get; set; }
    public DateTime ValidFrom { get; set; }
    public DateTime ValidTo { get; set; }
    public List<RoleMapping> Mappings { get; set; } = new();

    public ApiResourceExt? ApiResource { get; set; } // Navigation property to the ApiResource entity
}
