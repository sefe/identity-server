namespace IdentityServer.Abstraction.Contracts;

public interface IHasCreatedInfo
{
    DateTime? Created { get; set; }
    public string? CreatedBy { get; set; }
}
