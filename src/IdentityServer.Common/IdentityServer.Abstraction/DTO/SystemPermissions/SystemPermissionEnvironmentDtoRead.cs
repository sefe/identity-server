using System.Text.Json.Serialization;
using IdentityServer.Abstraction.Entities.IdentityServerConfig.SystemPermissions;

namespace IdentityServer.Abstraction.DTO.SystemPermissions;

public class SystemPermissionEnvironmentDtoRead : IDtoRead
{
    public int Id { get; set; }
    public required string Environment { get; set; }
    public int SystemPermissionId { get; set; }
    public string SystemPermissionName { get; set; } = string.Empty;
    public List<SystemPermissionRoleDtoRead> Permissions { get; set; } = new();
    [JsonIgnore]
    public bool IsInUse => TotalRegistrations > 0;
    public int ClientCount { get; set; }
    public int ApiResourceCount { get; set; }
    [JsonIgnore]
    public int TotalRegistrations => ClientCount + ApiResourceCount;
    [JsonIgnore]
    public string DisplayName => $"{SystemPermissionName} ({Environment})";
    [JsonIgnore]
    public string Owners => string.Join(", ", GetOwners());

    public string[] GetOwners()
    {
        return Permissions.Where(_ => _.RoleType == SystemPermissionRoleType.Writer)
                .Select(_ => _.Name).OrderBy(_ => _).ToArray();
    }
}
