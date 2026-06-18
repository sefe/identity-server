using IdentityServer.Abstraction.Contracts;

namespace IdentityServer.Data.DuendeEntityExtensions;

public class ClientPostLogoutRedirectUriExt : Duende.IdentityServer.EntityFramework.Entities.ClientPostLogoutRedirectUri, IHasCreatedInfo, IHasUpdatedInfo, IHasId<int>, IHasPeriodData
{
    public string? CreatedBy { get; set; }
    public DateTime? Created { get; set; }
    public DateTime? Updated { get; set; }
    public string? UpdatedBy { get; set; }

    // SQL Server temporal table period columns
    public DateTime ValidFrom { get; set; }
    public DateTime ValidTo { get; set; }
}
