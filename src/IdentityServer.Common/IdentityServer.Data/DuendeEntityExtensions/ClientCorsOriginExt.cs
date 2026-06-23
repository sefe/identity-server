// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

using Duende.IdentityServer.EntityFramework.Entities;
using IdentityServer.Abstraction.Contracts;

namespace IdentityServer.Data.DuendeEntityExtensions;

public class ClientCorsOriginExt : ClientCorsOrigin, IHasCreatedInfo, IHasUpdatedInfo, IHasId<int>, IHasPeriodData
{
    public DateTime? Created { get; set; }
    public string? CreatedBy { get; set; }
    public DateTime? Updated { get; set; }
    public string? UpdatedBy { get; set; }

    // SQL Server temporal table period columns
    public DateTime ValidFrom { get; set; }
    public DateTime ValidTo { get; set; }
}
