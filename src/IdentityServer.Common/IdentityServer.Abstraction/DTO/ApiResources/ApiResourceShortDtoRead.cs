using System.Text.Json.Serialization;
using IdentityServer.Abstraction.Contracts;
using IdentityServer.Abstraction.Entities.IdentityServerConfig.SystemPermissions;

namespace IdentityServer.Abstraction.DTO.ApiResources;

public class ApiResourceShortDtoRead : IDtoRead, IHasEnvironment, IHasCreatedInfo, IHasUpdatedInfo
{
    public int Id { get; set; }
    public string Name { get; set; } = default!;
    public string DisplayName { get; set; } = default!;
    public int SystemPermissionId { get; set; }
    public string SystemPermissionName { get; set; } = string.Empty;
    public int SystemPermissionEnvironmentId { get; set; }
    public string SystemPermissionEnvironmentName { get; set; } = string.Empty;
    public List<string> SystemPermissionEnvironmentOwnersList { get; set; } = new List<string>();
    [JsonIgnore]
    public string SystemPermissionEnvironmentOwners { get => string.Join(", ", SystemPermissionEnvironmentOwnersList); }
    public SystemPermissionRoleType AccessLevel { get; set; }
    public DateTime? Created { get; set; }
    public string? CreatedBy { get; set; }
    public DateTime? Updated { get; set; }
    public string? UpdatedBy { get; set; }
}

