// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

using IdentityServer.Abstraction.Contracts;

namespace IdentityServer.Data.DuendeEntityExtensions;

public class ApiScopeExt : Duende.IdentityServer.EntityFramework.Entities.ApiScope, IHasCreatedInfo, IHasUpdatedInfo, IHasPeriodData, IHasId<int>
{
    public string? CreatedBy { get; set; }
    public string? UpdatedBy { get; set; }
    public DateTime ValidFrom { get; set; }
    public DateTime ValidTo { get; set; }

    DateTime? IHasCreatedInfo.Created
    {
        get => Created;
        set => Created = value ?? DateTime.UtcNow;
    }
}
