// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

using Microsoft.EntityFrameworkCore;
using IdentityServer.Data.DbContexts;
using IdentityServer.Data.DuendeEntityExtensions;

namespace IdentityServer.Data.Repositories.Storage;

internal class ApiResourcePropertyScopeStorage : DbContextStorageBase<ApiResourceScopeExt>
{
    public ApiResourcePropertyScopeStorage(IdentityServerConfigurationDbContext dbContext)
        : base(dbContext, m => m.Id)
    {
    }

    protected override DbSet<ApiResourceScopeExt> DbSet => _dbContext.ApiResourceScopes;
}
