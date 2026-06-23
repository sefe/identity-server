// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

using Microsoft.EntityFrameworkCore;
using IdentityServer.Data.DbContexts;
using IdentityServer.Data.DuendeEntityExtensions;

namespace IdentityServer.Data.Repositories.Storage;

internal class ApiScopeStorage : DbContextStorageBase<ApiScopeExt>
{
    public ApiScopeStorage(IdentityServerConfigurationDbContext dbContext)
        : base(dbContext, m => m.Id)
    {
    }

    protected override DbSet<ApiScopeExt> DbSet => _dbContext.ApiScopes;

    public override Task<ApiScopeExt> UpdateAsync(ApiScopeExt resource)
    {
        resource.Updated = DateTime.UtcNow;
        return base.UpdateAsync(resource);
    }
}
