using Microsoft.Extensions.Logging;
using IdentityServer.Abstraction.Contracts;
using IdentityServer.Data.DbContexts;

namespace IdentityServer.Data.Services;

/// <summary>
/// Retrieve audit historic data about changes made to SystemPermission entities using <see cref="IdentityServerConfigurationDbContext"/> and stored procedures.
/// </summary>
internal class SystemPermissionAuditService : AuditServiceBase, ISystemPermissionAuditService
{
    protected override string SqlRawCommand => "EXEC GetSystemPermissionsLastModifiedTimestamp";

    public SystemPermissionAuditService(IdentityServerConfigurationDbContext dbContext, ILogger<SystemPermissionAuditService> logger)
        : base(dbContext, logger)
    {
    }
}
