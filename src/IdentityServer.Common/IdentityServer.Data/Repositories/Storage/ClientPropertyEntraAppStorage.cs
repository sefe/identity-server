using Microsoft.EntityFrameworkCore;
using IdentityServer.Data.DbContexts;
using IdentityServer.Data.DuendeEntityExtensions;

namespace IdentityServer.Data.Repositories.Storage;

internal class ClientPropertyEntraAppStorage : DbContextStorageBase<ClientEntraApp>
{
    public ClientPropertyEntraAppStorage(IdentityServerConfigurationDbContext dbContext)
        : base(dbContext, m => m.Id)
    {
    }

    protected override DbSet<ClientEntraApp> DbSet => _dbContext.ClientEntraApps;
}
