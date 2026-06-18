using Microsoft.Extensions.Logging;
using IdentityServer.Abstraction.Contracts;
using IdentityServer.Data.DbContexts;

namespace IdentityServer.Data.Services;

/// <summary>
/// Retrieve audit historic data about changes made to Client entities using <see cref="IdentityServerConfigurationDbContext"/> and stored procedures.
/// </summary>
internal class ClientAuditService : AuditServiceBase, IClientAuditService
{
    protected override string SqlRawCommand => "EXEC GetClientsLastModifiedTimestamp";

    public ClientAuditService(IdentityServerConfigurationDbContext dbContext, ILogger<ClientAuditService> logger)
        : base(dbContext, logger)
    {
    }
}
