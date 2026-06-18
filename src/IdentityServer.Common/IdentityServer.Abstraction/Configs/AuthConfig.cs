namespace IdentityServer.Abstraction.Configs;

public class AuthConfig : IAuthConfig
{
    public required string ContributorGroupId { get; set; }
    public required string ReaderGroupId { get; set; }
}