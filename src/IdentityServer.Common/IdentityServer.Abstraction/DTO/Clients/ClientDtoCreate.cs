using System.ComponentModel.DataAnnotations;
using IdentityServer.Abstraction.Entities.IdentityServerConfig;
using IdentityServer.Abstraction.Entities.Validation;

namespace IdentityServer.Abstraction.DTO.Clients;

public class ClientDtoCreate : IDtoCreate
{
    [Required]
    [StringLength(Constants.Limits.Client.Name.MaxLength, ErrorMessage = Constants.Limits.Client.Name.MaxLengthError)]
    [RegularExpression(Constants.Limits.Client.Name.Pattern, ErrorMessage = Constants.Limits.Client.Name.PatternError)]
    [Display(Name = "Identifier")]
    public required string ClientId { get; set; }

    [Required]
    [Display(Name = "Display Name")]
    [StringLength(Constants.Limits.Client.DisplayName.MaxLength, ErrorMessage = Constants.Limits.Client.DisplayName.MaxLengthError)]
    public required string ClientName { get; set; }

    [StringLength(Constants.Limits.Client.Description.MaxLength, ErrorMessage = Constants.Limits.Client.Description.MaxLengthError)]
    public string? Description { get; set; }

    public bool Enabled { get; set; } = true;
    public bool RequirePkce { get; set; } = true;
    public bool RequireClientSecret { get; set; } = true;

    [EnumDataType(typeof(ClientAccessTokenType))]
    [AllowedValues(ClientAccessTokenType.Jwt, ClientAccessTokenType.Reference, ErrorMessage = "Invalid Access Token Type.")]
    public ClientAccessTokenType AccessTokenType { get; set; } = ClientAccessTokenType.Jwt;

    [Required]
    [NotEmpty(ErrorMessage = "At least one Grant Type must be specified.")]
    [ClientGrantTypeValidation]
    [ClientGrantTypeCompatibilityValidation]
    public HashSet<string> AllowedGrantTypes { get; set; } = new();

    [Required]
    [Range(1, int.MaxValue, ErrorMessage = "The System Permission field is required.")]
    [Display(Name = "System Permission")]
    public int SystemPermissionEnvironmentId { get; set; }
}
