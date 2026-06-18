using Microsoft.EntityFrameworkCore;
using IdentityServer.Abstraction.Entities.IdentityServerConfig.SystemPermissions;
using IdentityServer.Data.DbContexts;

namespace IdentityServer.Data.Repositories.Storage;

internal class SystemPermissionRoleStorage : DbContextStorageBase<SystemPermissionRole>
{
    public SystemPermissionRoleStorage(IdentityServerConfigurationDbContext dbContext)
        : base(dbContext, m => m.Id)
    {
    }

    protected override DbSet<SystemPermissionRole> DbSet => _dbContext.SystemPermissionRole;
}
