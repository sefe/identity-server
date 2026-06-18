using System.ComponentModel.DataAnnotations;
using IdentityServer.Abstraction.DTO.Export;

namespace IdentityServer.Abstraction.DTO.Import;

public class ApiResourceRoleImportDto : RoleExportDto<ApiResourceRoleMappingValueObject>, IDtoRoleImport<ApiResourceRoleMappingValueObject>
{
    [Required]
    [AllowedValues(ImportStrategy.Replace, ImportStrategy.Add)]
    public ImportStrategy ImportStrategy { get; set; }
}
