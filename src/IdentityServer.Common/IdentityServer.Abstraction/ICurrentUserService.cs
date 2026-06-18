namespace IdentityServer.Abstraction;

public interface ICurrentUserService
{
    string? UserName { get; }
}
