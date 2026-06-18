using System.ComponentModel.DataAnnotations;

namespace IdentityServer.Abstraction.DTO.ApiResources;

public class ApiResourcePropertySecretDtoCreate : ApiResourcePropertyBaseDtoCreate
{
    [Required]
    [StringLength(Constants.Limits.Secret.Description.MaxLength, ErrorMessage = Constants.Limits.Secret.Description.MaxLengthError, MinimumLength = 1)]
    public string Description { get; set; } = default!;

    [Required]
    [Range(1, 99, ErrorMessage = "Validity period must be between 1 and 99 years.")]
    public int ValidityPeriodYears { get; set; }
}
