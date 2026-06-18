using Microsoft.EntityFrameworkCore;
using IdentityServer.Data.DbContexts;
using IdentityServer.Data.DuendeEntityExtensions;

namespace IdentityServer.Data.Repositories.Storage;

internal class ClientPropertyScopeStorage : DbContextStorageBase<ClientScopeExt>
{
    public ClientPropertyScopeStorage(IdentityServerConfigurationDbContext dbContext)
        : base(dbContext, m => m.Id)
    {
    }

    protected override DbSet<ClientScopeExt> DbSet => _dbContext.ClientScopes;
}
