namespace IdentityServer.Abstraction.Configs;

public interface IAuthConfig
{
    string ContributorGroupId { get; }

    string ReaderGroupId { get; }
}