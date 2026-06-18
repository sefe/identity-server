using IdentityServer.Abstraction.Contracts;

namespace IdentityServer.Data.DuendeEntityExtensions;

public class ClientSecretExt : Duende.IdentityServer.EntityFramework.Entities.ClientSecret, IHasCreatedInfo, IHasUpdatedInfo, IHasId<int>, IHasPeriodData
{
    public string? CreatedBy { get; set; }
    DateTime? IHasCreatedInfo.Created
    {
        get => Created;
        set => Created = value ?? DateTime.UtcNow;
    }
    public DateTime? Updated { get; set; }
    public string? UpdatedBy { get; set; }
    public string? Preview { get; set; }

    // SQL Server temporal table period columns
    public DateTime ValidFrom { get; set; }
    public DateTime ValidTo { get; set; }
}
