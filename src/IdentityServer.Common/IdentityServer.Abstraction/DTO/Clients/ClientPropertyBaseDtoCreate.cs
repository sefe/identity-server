using System.ComponentModel.DataAnnotations;

namespace IdentityServer.Abstraction.DTO.Clients;

public abstract class ClientPropertyBaseDtoCreate : IDtoCreate
{
    [Required]
    [Range(1, int.MaxValue, ErrorMessage = "Client Id must be a positive integer")]
    public int ClientId { get; set; }
}
