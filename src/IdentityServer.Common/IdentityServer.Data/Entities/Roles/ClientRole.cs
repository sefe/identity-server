// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

using IdentityServer.Abstraction.Contracts;
using IdentityServer.Data.DuendeEntityExtensions;

namespace IdentityServer.Data.Entities.Roles;

public class ClientRole : IHasCreatedInfo, IHasUpdatedInfo, IHasId<int>, IHasPeriodData
{
    public int Id { get; set; }
    public int ClientId { get; set; }
    public required string RoleName { get; set; }
    public DateTime Created { get; set; }
    public string? CreatedBy { get; set; }
    public DateTime? Updated { get; set; }
    public string? UpdatedBy { get; set; }
    public List<ClientRoleMapping> Mappings { get; set; } = new();

    // SQL Server System-Versioning temporal table columns
    public DateTime ValidFrom { get; set; }
    public DateTime ValidTo { get; set; }

    DateTime? IHasCreatedInfo.Created
    {
        get => Created;
        set => Created = value ?? DateTime.UtcNow;
    }

    public ClientExt? Client { get; set; } // Navigation property to the Client entity
}
