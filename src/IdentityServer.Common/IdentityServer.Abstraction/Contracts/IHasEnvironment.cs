using IdentityServer.Abstraction.Entities.IdentityServerConfig.SystemPermissions;

namespace IdentityServer.Abstraction.Contracts;

public interface IHasEnvironment
{
    int SystemPermissionId { get; set; }
    string SystemPermissionName { get; set; }

    int SystemPermissionEnvironmentId { get; set; }
    string SystemPermissionEnvironmentName { get; set; }

    public SystemPermissionRoleType AccessLevel { get; set; }
}
