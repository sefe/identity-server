using IdentityServer.Abstraction.Contracts;

namespace IdentityServer.Data.DuendeEntityExtensions;

public class ClientEntraApp : IHasCreatedInfo, IHasUpdatedInfo, IHasId<int>, IHasPeriodData
{
    public int Id { get; set; }
    public int ClientId { get; set; }
    public required string AppId { get; set; }
    public required string AppName { get; set; }
    public DateTime? Created { get; set; }
    public string? CreatedBy { get; set; }
    public DateTime? Updated { get; set; }
    public string? UpdatedBy { get; set; }

    public ClientExt? Client { get; set; }

    // SQL Server temporal table period columns
    public DateTime ValidFrom { get; set; }
    public DateTime ValidTo { get; set; }
}
