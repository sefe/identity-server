using IdentityServer.Abstraction.DTO.Export;

namespace IdentityServer.AdminPortal.Web.Models.RoleImport;

public class RoleMappingComparisonModel
{
    public required RoleComparisonModel Parent { get; set; }
    public ComparisonState State { get; set; } = ComparisonState.Unchanged;
    public required RoleMappingValueObject Imported { get; set; }
    public required RoleMappingValueObject Existing { get; set; }
}
