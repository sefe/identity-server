using System.ComponentModel.DataAnnotations;
using IdentityServer.Abstraction.Entities.Validation;

namespace IdentityServer.Abstraction.DTO.Clients;

public class ClientPropertyRedirectUriDtoCreate : ClientPropertyBaseDtoCreate
{
    [Required]
    [StringLength(400, ErrorMessage = "Redirect URI cannot exceed 400 characters.")]
    [ClientRedirectUriValidation("Redirect URI")]
    public required string RedirectUri { get; set; }
}
