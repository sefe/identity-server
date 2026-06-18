using System.ComponentModel.DataAnnotations;
using IdentityServer.Abstraction.Entities.IdentityServerConfig;

namespace IdentityServer.Abstraction.DTO.Clients;

public class ClientPropertyRoleMappingDtoCreate : ClientPropertyBaseDtoCreate
{
    [Required]
    [Range(1, int.MaxValue, ErrorMessage = "Application Role Id must be a positive integer")]
    public int ClientRoleId { get; set; }

    [EnumDataType(typeof(ClientRoleMapType))]
    [AllowedValues(ClientRoleMapType.SecurityGroup, ClientRoleMapType.UserObjectId, ErrorMessage = "Invalid Role Mapping Type.")]
    public ClientRoleMapType MappingType { get; set; }

    [Required]
    [StringLength(Constants.Limits.RoleMapping.Value.MaxLength, ErrorMessage = Constants.Limits.RoleMapping.Value.MaxLengthError, MinimumLength = 1)]
    public string Value { get; set; } = default!;
}
