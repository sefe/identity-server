using IdentityServer.Abstraction.DTO.ApiResources;

namespace IdentityServer.AdminPortal.Web.Models;

public class ApiResourceMappedRole
{
    public int ApiResourceRoleId { get; set; }
    public required string ApiResourceRoleName { get; set; }
    public required ApiResourcePropertyRoleMappingDtoRead RoleMapping { get; set; }

    public string RoleMappingValue => RoleMapping.Value;
    public string? RoleMappingDescription => RoleMapping.Description;
}
