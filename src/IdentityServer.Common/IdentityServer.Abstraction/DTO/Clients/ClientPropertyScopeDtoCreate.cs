using System.ComponentModel.DataAnnotations;

namespace IdentityServer.Abstraction.DTO.Clients;

public class ClientPropertyScopeDtoCreate : ClientPropertyBaseDtoCreate
{
    [Required]
    [StringLength(200, ErrorMessage = "Scope cannot exceed 200 characters.")]
    public required string Scope { get; set; }
}
