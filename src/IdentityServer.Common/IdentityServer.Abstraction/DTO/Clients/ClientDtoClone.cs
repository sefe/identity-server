using System.ComponentModel.DataAnnotations;

namespace IdentityServer.Abstraction.DTO.Clients;

public class ClientDtoClone : IDtoClone
{
    [Required]
    [Range(1, int.MaxValue, ErrorMessage = "Id must be a positive integer greater than 0")]
    public int Id { get; set; }

    [Required]
    [StringLength(Constants.Limits.Client.Name.MaxLength, ErrorMessage = Constants.Limits.Client.Name.MaxLengthError)]
    [RegularExpression(Constants.Limits.Client.Name.Pattern, ErrorMessage = Constants.Limits.Client.Name.PatternError)]
    [Display(Name = "Identifier")]
    public required string ClientId { get; set; }

    [Required]
    [Display(Name = "Display Name")]
    [StringLength(Constants.Limits.Client.DisplayName.MaxLength, ErrorMessage = Constants.Limits.Client.DisplayName.MaxLengthError)]
    public required string ClientName { get; set; }

    [Required]
    [Range(1, int.MaxValue, ErrorMessage = "The System Permission field is required.")]
    [Display(Name = "System Permission")]
    public int SystemPermissionEnvironmentId { get; set; }
}
