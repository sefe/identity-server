using System.ComponentModel.DataAnnotations;

namespace IdentityServer.Abstraction.DTO.ApiResources;

public class ApiResourcePropertyScopeDtoCreate : ApiResourcePropertyBaseDtoCreate
{
    [Required]
    [StringLength(Constants.Limits.ApiScope.Name.MaxLength, ErrorMessage = Constants.Limits.ApiScope.Name.MaxLengthError, MinimumLength = 1)]
    [RegularExpression(Constants.Limits.ApiScope.Name.Pattern, ErrorMessage = Constants.Limits.ApiScope.Name.PatternError)]
    [Display(Name = "Identifier")]
    public string Name { get; set; } = default!;

    [Required]
    [StringLength(Constants.Limits.ApiScope.DisplayName.MaxLength, ErrorMessage = Constants.Limits.ApiScope.DisplayName.LengthRangeError, MinimumLength = 1)]
    [Display(Name = "Display Name")]
    public string DisplayName { get; set; } = default!;

    [StringLength(Constants.Limits.ApiScope.Description.MaxLength, ErrorMessage = Constants.Limits.ApiScope.Description.MaxLengthError)]
    public string? Description { get; set; }
    public bool Enabled { get; set; } = true;
    public bool Required { get; set; } = false;
}
