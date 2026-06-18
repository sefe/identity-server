using Microsoft.EntityFrameworkCore;
using IdentityServer.Data.DbContexts;
using IdentityServer.Data.DuendeEntityExtensions;

namespace IdentityServer.Data.Repositories.Storage;

internal class ClientPropertyPostLogoutRedirectUriStorage : DbContextStorageBase<ClientPostLogoutRedirectUriExt>
{
    public ClientPropertyPostLogoutRedirectUriStorage(IdentityServerConfigurationDbContext dbContext)
        : base(dbContext, m => m.Id)
    {
    }

    protected override DbSet<ClientPostLogoutRedirectUriExt> DbSet => _dbContext.ClientPostLogoutRedirectUris;
}
