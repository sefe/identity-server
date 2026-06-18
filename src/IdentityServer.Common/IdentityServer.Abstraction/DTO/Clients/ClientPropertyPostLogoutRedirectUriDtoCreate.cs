using System.ComponentModel.DataAnnotations;
using IdentityServer.Abstraction.Entities.Validation;

namespace IdentityServer.Abstraction.DTO.Clients;

public class ClientPropertyPostLogoutRedirectUriDtoCreate : ClientPropertyBaseDtoCreate
{
    [Required]
    [StringLength(400, ErrorMessage = "Post-Logout Redirect URI cannot exceed 400 characters.")]
    [ClientRedirectUriValidation("Post-Logout Redirect URI")]
    public required string PostLogoutRedirectUri { get; set; }
}
