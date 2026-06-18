using IdentityServer.Abstraction.Entities.IdentityServerConfig.SystemPermissions;

namespace IdentityServer.Abstraction.DTO.SystemPermissions;

public class SystemPermissionRoleDtoRead : IDtoRead
{
    public int Id { get; set; }
    public required string OId { get; set; }
    public required string Name { get; set; }
    public int SystemPermissionEnvironmentId { get; set; }
    public SystemPermissionRoleType RoleType { get; set; }
}