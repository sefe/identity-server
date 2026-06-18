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
