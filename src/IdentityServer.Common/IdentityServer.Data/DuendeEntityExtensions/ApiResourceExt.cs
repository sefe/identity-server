using IdentityServer.Abstraction.Contracts;
using IdentityServer.Abstraction.Entities.IdentityServerConfig.SystemPermissions;
using IdentityServer.Data.Entities.Roles;

namespace IdentityServer.Data.DuendeEntityExtensions;

public class ApiResourceExt : Duende.IdentityServer.EntityFramework.Entities.ApiResource, IPermissionBasedEntity, IHasCreatedInfo, IHasUpdatedInfo, IHasPeriodData, IHasId<int>
{
    public ApiResourceExt()
    {
        // Only set important defaults which differ from the base class
        RequireResourceIndicator = false;
        ShowInDiscoveryDocument = false;
    }

    public int SystemPermissionEnvironmentId { get; set; }
    public required SystemPermissionEnvironment SystemPermissionEnvironment { get; set; }
    public string? CreatedBy { get; set; }
    public string? UpdatedBy { get; set; }

    DateTime? IHasCreatedInfo.Created
    {
        get => Created;
        set => Created = value ?? DateTime.UtcNow;
    }

    public DateTime ValidFrom { get; set; }
    public DateTime ValidTo { get; set; }

    public override string ToString()
    {
        return $"API Resource '{Id}'";
    }

    public List<ApiResourceRole> Roles { get; set; } = new(); // Navigation property for roles associated with the API resource
}
