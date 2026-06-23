// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

using Microsoft.EntityFrameworkCore;
using IdentityServer.Data.DbContexts;
using IdentityServer.Data.Entities.Roles;

namespace IdentityServer.Data.Repositories.Storage;

internal class ClientPropertyRoleMappingStorage : DbContextStorageBase<ClientRoleMapping>
{
    public ClientPropertyRoleMappingStorage(IdentityServerConfigurationDbContext dbContext)
        : base(dbContext, m => m.Id)
    {
    }

    protected override DbSet<ClientRoleMapping> DbSet => _dbContext.ClientRoleMappings;

    protected override IQueryable<ClientRoleMapping> Query()
    {
        return DbSet
            .Include(m => m.Role);
    }
}
