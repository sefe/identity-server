using IdentityServer.Abstraction.DTO;
using IdentityServer.Abstraction.DTO.Export;

namespace IdentityServer.AdminPortal.Web.Models.RoleImport;

public abstract class ImportRoleModel<TDto, TRoleMapping> : ImportModel<TDto> where TDto : IDtoRoleImport<TRoleMapping> where TRoleMapping : RoleMappingValueObject
{
    public List<RoleComparisonModel> RoleComparisons { get; set; } = new();
}
