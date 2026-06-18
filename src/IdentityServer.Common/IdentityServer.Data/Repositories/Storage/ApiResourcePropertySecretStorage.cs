using Microsoft.EntityFrameworkCore;
using IdentityServer.Data.DbContexts;
using IdentityServer.Data.DuendeEntityExtensions;

namespace IdentityServer.Data.Repositories.Storage;

internal class ApiResourcePropertySecretStorage : DbContextStorageBase<ApiResourceSecretExt>
{
    public ApiResourcePropertySecretStorage(IdentityServerConfigurationDbContext dbContext)
        : base(dbContext, m => m.Id)
    {
    }

    protected override DbSet<ApiResourceSecretExt> DbSet => _dbContext.ApiResourceSecrets;
}
