// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

using Microsoft.Extensions.Logging;
using IdentityServer.Abstraction.Contracts;
using IdentityServer.Data.DbContexts;

namespace IdentityServer.Data.Services;

/// <summary>
/// Retrieve audit historic data about changes made to ApiResource entities using <see cref="IdentityServerConfigurationDbContext"/> and stored procedures.
/// </summary>
internal class ApiResourceAuditService : AuditServiceBase, IApiResourceAuditService
{
    protected override string SqlRawCommand => "EXEC GetApiResourcesLastModifiedTimestamp";

    public ApiResourceAuditService(IdentityServerConfigurationDbContext dbContext, ILogger<ApiResourceAuditService> logger)
        : base(dbContext, logger)
    {
    }
}
