using Microsoft.EntityFrameworkCore;
using IdentityServer.Abstraction.Entities.IdentityServerConfig.SystemPermissions;
using IdentityServer.Data.DbContexts;

namespace IdentityServer.Data.Repositories.Storage;

internal class SystemPermissionStorage : DbContextStorageBase<SystemPermission>
{
    public SystemPermissionStorage(IdentityServerConfigurationDbContext dbContext)
        : base(dbContext, m => m.Id)
    {
    }

    protected override DbSet<SystemPermission> DbSet => _dbContext.SystemPermissions;

    protected override IQueryable<SystemPermission> Query()
    {
        return _dbContext.SystemPermissions
                .Include(x => x.Environments)
                .ThenInclude(pe => pe.Permissions);
    }

    public override IQueryable<SystemPermission> ShallowQuery()
    {
        return Query().OrderBy(x => x.Id);
    }

    public override Task<SystemPermission> AddAsync(SystemPermission resource)
    {
        // don't allow saving child entries
        resource.Environments = new List<SystemPermissionEnvironment>();

        return base.AddAsync(resource);
    }
}
