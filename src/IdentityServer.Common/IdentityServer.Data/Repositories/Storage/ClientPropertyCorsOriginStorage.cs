using Microsoft.EntityFrameworkCore;
using IdentityServer.Data.DbContexts;
using IdentityServer.Data.DuendeEntityExtensions;

namespace IdentityServer.Data.Repositories.Storage;

internal class ClientPropertyCorsOriginStorage : DbContextStorageBase<ClientCorsOriginExt>
{
    public ClientPropertyCorsOriginStorage(IdentityServerConfigurationDbContext dbContext)
        : base(dbContext, m => m.Id)
    {
    }

    protected override DbSet<ClientCorsOriginExt> DbSet => _dbContext.ClientCorsOrigins;
}
