using IdentityServer.Abstraction.DTO.Export;
using IdentityServer.Abstraction.DTO.Import;

namespace IdentityServer.AdminPortal.Web.Models.RoleImport;

public class ClientRoleImportModel : ImportRoleModel<ClientRoleImportDto, ClientRoleMappingValueObject>
{
    public override OperationStatus<ClientRoleImportDto> FileParsingStatus { get; set; } = new OperationStatus<ClientRoleImportDto> { Result = new() };
}
