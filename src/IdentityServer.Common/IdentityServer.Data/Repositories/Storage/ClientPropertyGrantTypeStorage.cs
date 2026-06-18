using Microsoft.EntityFrameworkCore;
using IdentityServer.Data.DbContexts;
using IdentityServer.Data.DuendeEntityExtensions;

namespace IdentityServer.Data.Repositories.Storage;

internal class ClientPropertyGrantTypeStorage : DbContextStorageBase<ClientGrantTypeExt>
{
    public ClientPropertyGrantTypeStorage(IdentityServerConfigurationDbContext dbContext)
        : base(dbContext, m => m.Id)
    {
    }

    protected override DbSet<ClientGrantTypeExt> DbSet => _dbContext.ClientGrantTypes;
}
