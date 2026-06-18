using IdentityServer.Abstraction.Contracts;
using IdentityServer.Abstraction.Entities.IdentityServerConfig;

namespace IdentityServer.Data.Entities.Roles;

public class RoleMapping : IHasCreatedInfo, IHasUpdatedInfo, IHasPeriodData, IHasId<int>
{
    public int Id { get; set; }
    public int ApiResourceRoleId { get; set; }
    public RoleMapType MappingType { get; set; }
    public int RoleMappingTypeId { get; set; }
    public required string Value { get; set; }
    public string? Description { get; set; }
    public DateTime? Created { get; set; }
    public string? CreatedBy { get; set; }
    public DateTime? Updated { get; set; }
    public string? UpdatedBy { get; set; }
    public DateTime ValidFrom { get; set; }
    public DateTime ValidTo { get; set; }

    public ApiResourceRole? Role { get; set; } // Navigation property to the ApiResourceRole entity
}
