using System.ComponentModel.DataAnnotations;

namespace IdentityServer.Abstraction.DTO.ApiResources;

public class ApiResourceDtoClone : IDtoClone
{
    [Required]
    [Range(1, int.MaxValue, ErrorMessage = "Id must be a positive integer greater than 0")]
    public int Id { get; set; }

    [Required]
    [StringLength(Constants.Limits.ApiResource.Name.MaxLength, ErrorMessage = Constants.Limits.ApiResource.Name.MaxLengthError)]
    [RegularExpression(Constants.Limits.ApiResource.Name.Pattern, ErrorMessage = Constants.Limits.ApiResource.Name.PatternError)]
    [Display(Name = "Identifier")]
    public string Name { get; set; } = default!;

    [Required]
    [StringLength(Constants.Limits.ApiResource.DisplayName.MaxLength, ErrorMessage = Constants.Limits.ApiResource.DisplayName.MaxLengthError)]
    [Display(Name = "Display Name")]
    public string DisplayName { get; set; } = default!;

    [Required]
    [Range(1, int.MaxValue, ErrorMessage = "The System Permission field is required.")]
    [Display(Name = "System Permission")]
    public int SystemPermissionEnvironmentId { get; set; }
}
