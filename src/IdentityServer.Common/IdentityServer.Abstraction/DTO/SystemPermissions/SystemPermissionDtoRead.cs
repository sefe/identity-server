using IdentityServer.Abstraction.Entities.IdentityServerConfig.SystemPermissions;

namespace IdentityServer.Abstraction.DTO.SystemPermissions;

public class SystemPermissionDtoRead : IDtoRead
{
    public int Id { get; set; }
    public required string Name { get; set; }
    public required string Description { get; set; }
    public DateTime Created { get; set; }
    public DateTime? Updated { get; set; }
    public string? UpdateReason { get; set; }
    public List<SystemPermissionEnvironmentDtoRead> Environments { get; set; } = new();
    public SystemPermissionRoleType AccessLevel { get; set; } = SystemPermissionRoleType.None;
    public bool IsInUse => Environments.Any(e => e.IsInUse);
    public int TotalRegistrations => Environments.Sum(e => e.TotalRegistrations);
}
