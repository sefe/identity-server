using System.ComponentModel.DataAnnotations;
using IdentityServer.Abstraction.Entities.IdentityServerConfig.SystemPermissions;

namespace IdentityServer.Abstraction.DTO.SystemPermissions;

public class SystemPermissionEnvironmentDtoCreate : IDtoCreate
{
    [Required]
    [SystemPermissionEnvironmentNameValidation]
    public required string Environment { get; set; }

    [Required]
    [Range(1, int.MaxValue, ErrorMessage = "System Permission Id must be a positive integer greater than 0")]
    public int SystemPermissionId { get; set; }
}