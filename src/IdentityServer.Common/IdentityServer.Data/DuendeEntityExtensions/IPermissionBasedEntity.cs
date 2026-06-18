using IdentityServer.Abstraction.Entities.IdentityServerConfig.SystemPermissions;

namespace IdentityServer.Data.DuendeEntityExtensions;

public interface IPermissionBasedEntity
{
    int SystemPermissionEnvironmentId { get; set; }

    SystemPermissionEnvironment SystemPermissionEnvironment { get; set; }
}
