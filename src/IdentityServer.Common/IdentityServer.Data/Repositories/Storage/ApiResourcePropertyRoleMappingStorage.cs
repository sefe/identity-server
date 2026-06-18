using Microsoft.EntityFrameworkCore;
using IdentityServer.Data.DbContexts;
using IdentityServer.Data.Entities.Roles;

namespace IdentityServer.Data.Repositories.Storage;

internal class ApiResourcePropertyRoleMappingStorage : DbContextStorageBase<RoleMapping>
{
    public ApiResourcePropertyRoleMappingStorage(IdentityServerConfigurationDbContext dbContext)
        : base(dbContext, m => m.Id)
    {
    }

    protected override DbSet<RoleMapping> DbSet => _dbContext.RoleMappings;

    protected override IQueryable<RoleMapping> Query()
    {
        return DbSet
            .Include(m => m.Role);
    }
}
