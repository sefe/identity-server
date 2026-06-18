using System.ComponentModel.DataAnnotations;

namespace IdentityServer.Abstraction.DTO.SystemPermissions;

public class SystemPermissionDtoCreate : IDtoCreate
{
    [Required]
    [Display(Name = "System Name")]
    [StringLength(Constants.Limits.SystemPermission.Name.MaxLength, ErrorMessage = Constants.Limits.SystemPermission.Name.MaxLengthError)]
    [RegularExpression(Constants.Limits.SystemPermission.Name.Pattern, ErrorMessage = Constants.Limits.SystemPermission.Name.PatternError)]
    public string Name { get; set; } = default!;

    [Required]
    [StringLength(Constants.Limits.SystemPermission.Description.MaxLength, ErrorMessage = Constants.Limits.SystemPermission.Description.MaxLengthError)]
    public string Description { get; set; } = default!;
}
