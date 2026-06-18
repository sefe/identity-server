using Duende.IdentityServer.EntityFramework.DbContexts;
using Microsoft.AspNetCore.DataProtection.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore;

namespace IdentityServer.Data.DbContexts;

public class IdentityServerOperationalDbContext : PersistedGrantDbContext<IdentityServerOperationalDbContext>, IDataProtectionKeyContext
{
    public IdentityServerOperationalDbContext(DbContextOptions<IdentityServerOperationalDbContext> options) : base(options)
    {
    }

    public DbSet<DataProtectionKey> DataProtectionKeys { get; set; }

    protected override void OnModelCreating(ModelBuilder modelBuilder)
    {
        base.OnModelCreating(modelBuilder);

        // Configure the table name and other properties if necessary
        modelBuilder.Entity<DataProtectionKey>()
            .ToTable("DataProtectionKeys");
    }
}
