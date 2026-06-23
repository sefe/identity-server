// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

using Microsoft.EntityFrameworkCore;
using IdentityServer.Data.DbContexts;
using IdentityServer.Data.DuendeEntityExtensions;
using IdentityServer.Data.Entities.Roles;

namespace IdentityServer.Data.Repositories.Storage;

internal class ApiResourcePropertyRoleStorage : DbContextStorageBase<ApiResourceRole>
{
    public ApiResourcePropertyRoleStorage(IdentityServerConfigurationDbContext dbContext)
        : base(dbContext, m => m.Id)
    {
    }

    protected override DbSet<ApiResourceRole> DbSet => _dbContext.ApiResourceRoles;

    protected override IQueryable<ApiResourceRole> Query()
    {
        return DbSet
            .Include(m => m.ApiResource);
    }
}
