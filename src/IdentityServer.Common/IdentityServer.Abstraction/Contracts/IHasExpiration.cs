namespace IdentityServer.Abstraction.Contracts;

public interface IHasExpiration
{
    DateTime? Expiration { get; set; }
}
