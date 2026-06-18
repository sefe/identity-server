using System.Text.Json.Serialization;
using IdentityServer.Abstraction.Contracts;
using IdentityServer.Abstraction.Entities.IdentityServerConfig.SystemPermissions;

namespace IdentityServer.Abstraction.DTO.SystemPermissions;

public class SystemPermissionShortDtoRead : IDtoRead, IHasCreatedInfo, IHasUpdatedInfo
{
    public int Id { get; set; }
    public required string Name { get; set; }
    public required string Description { get; set; }
    public DateTime? Created { get; set; }
    public string? CreatedBy { get; set; }
    public DateTime? Updated { get; set; }
    public string? UpdatedBy { get; set; }
    public SystemPermissionRoleType AccessLevel { get; set; } = SystemPermissionRoleType.None;
    [JsonIgnore]
    public bool IsInUse => TotalRegistrations > 0;
    public int TotalRegistrations { get; set; }
    public List<string> EnvironmentNamesList { get; set; } = new List<string>();
    [JsonIgnore]
    public string EnvironmentNames { get => string.Join(", ", EnvironmentNamesList.OrderBy(n => n)); }
    public List<int> EnvironmentIds { get; set; } = new();
    public List<string> OwnersList { get; set; } = new List<string>();
    [JsonIgnore]
    public string Owners { get => string.Join(", ", OwnersList ?? new()); }
}
