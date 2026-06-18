using System.ComponentModel.DataAnnotations;
using IdentityServer.Abstraction.Entities.Validation;

namespace IdentityServer.Abstraction.DTO.Clients;

public class ClientPropertyGrantDtoCreate : ClientPropertyBaseDtoCreate
{
    [Required]
    [ClientGrantTypeValidation]
    public required string GrantType { get; set; }
}
