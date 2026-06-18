namespace IdentityServer.Abstraction.Contracts;

public interface IHasUpdatedInfo
{
    DateTime? Updated { get; set; }
    public string? UpdatedBy { get; set; }
}
