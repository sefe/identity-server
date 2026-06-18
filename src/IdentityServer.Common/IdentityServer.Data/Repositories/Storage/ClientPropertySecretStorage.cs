using Microsoft.EntityFrameworkCore;
using IdentityServer.Data.DbContexts;
using IdentityServer.Data.DuendeEntityExtensions;

namespace IdentityServer.Data.Repositories.Storage;

internal class ClientPropertySecretStorage : DbContextStorageBase<ClientSecretExt>
{
    public ClientPropertySecretStorage(IdentityServerConfigurationDbContext dbContext)
        : base(dbContext, m => m.Id)
    {
    }

    protected override DbSet<ClientSecretExt> DbSet => _dbContext.ClientSecrets;
}
