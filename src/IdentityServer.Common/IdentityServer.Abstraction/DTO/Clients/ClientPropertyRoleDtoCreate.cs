using System.ComponentModel.DataAnnotations;

namespace IdentityServer.Abstraction.DTO.Clients;

public class ClientPropertyRoleDtoCreate : ClientPropertyBaseDtoCreate
{
    [Required]
    [StringLength(Constants.Limits.Role.Name.MaxLength, ErrorMessage = Constants.Limits.Role.Name.MaxLengthError, MinimumLength = 1)]
    [RegularExpression(Constants.Limits.Role.Name.Pattern, ErrorMessage = Constants.Limits.Role.Name.PatternError)]
    [Display(Name = "Role Name")]
    public string RoleName { get; set; } = default!;
}
