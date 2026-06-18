using Microsoft.EntityFrameworkCore;
using IdentityServer.Data.DbContexts;
using IdentityServer.Data.DuendeEntityExtensions;

namespace IdentityServer.Data.Repositories.Storage;

internal class ApiResourceStorage : DbContextStorageBase<ApiResourceExt>
{
    public ApiResourceStorage(IdentityServerConfigurationDbContext dbContext)
        : base(dbContext, m => m.Id)
    {
    }

    protected override DbSet<ApiResourceExt> DbSet => _dbContext.ApiResources;

    protected override IQueryable<ApiResourceExt> Query()
    {
        return _dbContext.ApiResources
            .Include(x => x.Scopes)
            .Include(x => x.Secrets)
            .Include(x => x.Roles)
                .ThenInclude(xy => xy.Mappings)
            .Include(c => c.SystemPermissionEnvironment)
                .ThenInclude(xz => xz.SystemPermission);
    }

    public override IQueryable<ApiResourceExt> ShallowQuery()
    {
        return _dbContext.ApiResources
            .Include(x => x.SystemPermissionEnvironment)
                .ThenInclude(xz => xz.SystemPermission)
            .Include(x => x.SystemPermissionEnvironment)
                .ThenInclude(xz => xz.Permissions)
            .OrderBy(x => x.Id); // for Skip/Take consistency
    }
}
