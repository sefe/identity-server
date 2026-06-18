using IdentityServer.Abstraction.Contracts;
using IdentityServer.Abstraction.Entities.IdentityServerConfig;

namespace IdentityServer.Data.Entities.Roles;

public class ClientRoleMapping : IHasCreatedInfo, IHasUpdatedInfo, IHasPeriodData, IHasId<int>
{
    public int Id { get; set; }
    public int ClientRoleId { get; set; }
    public ClientRoleMapType MappingType { get; set; }
    public required string Value { get; set; }
    public string? Description { get; set; }
    public DateTime? Created { get; set; }
    public string? CreatedBy { get; set; }
    public DateTime? Updated { get; set; }
    public string? UpdatedBy { get; set; }

    // SQL Server System-Versioning temporal table columns
    public DateTime ValidFrom { get; set; }
    public DateTime ValidTo { get; set; }

    public ClientRole? Role { get; set; } // Navigation property to the ClientRole entity
}
