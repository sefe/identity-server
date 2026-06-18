using IdentityServer.Abstraction.Contracts;

namespace IdentityServer.Data.DuendeEntityExtensions;

public class ApiResourceScopeExt : Duende.IdentityServer.EntityFramework.Entities.ApiResourceScope, IHasCreatedInfo, IHasUpdatedInfo, IHasPeriodData, IHasId<int>
{
    public DateTime? Created { get; set; }
    public string? CreatedBy { get; set; }
    public DateTime? Updated { get; set; }
    public string? UpdatedBy { get; set; }
    public DateTime ValidFrom { get; set; }
    public DateTime ValidTo { get; set; }
}
