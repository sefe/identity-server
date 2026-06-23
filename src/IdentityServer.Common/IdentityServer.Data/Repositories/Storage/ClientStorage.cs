// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

using Microsoft.EntityFrameworkCore;
using IdentityServer.Data.DbContexts;
using IdentityServer.Data.DuendeEntityExtensions;

namespace IdentityServer.Data.Repositories.Storage;

internal class ClientStorage : DbContextStorageBase<ClientExt>
{
    public ClientStorage(IdentityServerConfigurationDbContext dbContext)
        : base(dbContext, m => m.Id)
    {
    }

    protected override DbSet<ClientExt> DbSet => _dbContext.Clients;

    protected override IQueryable<ClientExt> Query()
    {
        return _dbContext.Clients
                .Include(c => c.AllowedCorsOrigins)
                .Include(c => c.AllowedGrantTypes)
                .Include(c => c.EntraApps)
                .Include(c => c.RedirectUris)
                .Include(c => c.PostLogoutRedirectUris)
                .Include(c => c.AllowedScopes)
                .Include(c => c.ClientSecrets)
                .Include(c => c.Roles)
                    .ThenInclude(c => c.Mappings)
                .Include(c => c.SystemPermissionEnvironment)
                    .ThenInclude(xz => xz.SystemPermission);
    }

    public override IQueryable<ClientExt> ShallowQuery()
    {
        return _dbContext.Clients
            .Include(x => x.SystemPermissionEnvironment)
                .ThenInclude(xz => xz.SystemPermission)
            .Include(x => x.SystemPermissionEnvironment)
                .ThenInclude(xz => xz.Permissions)
            .OrderBy(x => x.Id); // for Skip/Take consistency
    }
}
