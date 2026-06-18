using IdentityServer.Abstraction.DTO.Export;
using IdentityServer.Abstraction.DTO.Import;

namespace IdentityServer.AdminPortal.Web.Models.RoleImport;

public class ApiResourceRoleImportModel : ImportRoleModel<ApiResourceRoleImportDto, ApiResourceRoleMappingValueObject>
{
    public override OperationStatus<ApiResourceRoleImportDto> FileParsingStatus { get; set; } = new OperationStatus<ApiResourceRoleImportDto> { Result = new() };
}
