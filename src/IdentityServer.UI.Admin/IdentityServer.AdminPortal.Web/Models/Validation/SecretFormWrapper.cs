using System.ComponentModel.DataAnnotations;
using System.Runtime.Serialization;

namespace IdentityServer.AdminPortal.Web.Models.Validation;

[UniquePropertyValue(nameof(SecretDescription), "Secret")]
public class SecretFormWrapper : IHasUniquePropertyValue
{
    [Required(ErrorMessage = "The Description field is required.")]
    [StringLength(Abstraction.Constants.Limits.Secret.Description.MaxLength, ErrorMessage = Abstraction.Constants.Limits.Secret.Description.MaxLengthError, MinimumLength = 1)]
    public string SecretDescription { get; set; } = default!;

    [Required(ErrorMessage = "The Validity Period field is required.")]
    [Range(1, 99, ErrorMessage = "Validity period must be between 1 and 99 years.")]
    public int ValidityPeriodYears { get; set; } = 2;

    [IgnoreDataMember]
    public string UniqueProperty => SecretDescription;

    [IgnoreDataMember]
    public HashSet<string> AlreadyExistingUniquePropertyValues { get; set; } = new();
}
