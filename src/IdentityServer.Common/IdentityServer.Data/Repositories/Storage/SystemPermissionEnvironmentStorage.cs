// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

using Microsoft.EntityFrameworkCore;
using IdentityServer.Abstraction.Entities.IdentityServerConfig.SystemPermissions;
using IdentityServer.Data.DbContexts;

namespace IdentityServer.Data.Repositories.Storage;

internal class SystemPermissionEnvironmentStorage : DbContextStorageBase<SystemPermissionEnvironment>
{
    public SystemPermissionEnvironmentStorage(IdentityServerConfigurationDbContext dbContext)
        : base(dbContext, m => m.Id)
    {
    }

    protected override DbSet<SystemPermissionEnvironment> DbSet => _dbContext.SystemPermissionEnvironments;

    protected override IQueryable<SystemPermissionEnvironment> Query()
    {
        return _dbContext.SystemPermissionEnvironments
                .Include(pe => pe.Permissions)
                .Include(pe => pe.SystemPermission);
    }

    public override IQueryable<SystemPermissionEnvironment> ShallowQuery()
    {
        return _dbContext.SystemPermissionEnvironments
                .Include(pe => pe.SystemPermission)
                .OrderBy(x => x.Id); // for Skip/Take consistency
    }

    public override Task<SystemPermissionEnvironment> AddAsync(SystemPermissionEnvironment resource)
    {
        // don't allow saving child entries
        resource.Permissions = new List<SystemPermissionRole>();

        return base.AddAsync(resource);
    }
}
