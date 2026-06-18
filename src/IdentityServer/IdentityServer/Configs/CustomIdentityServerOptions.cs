using Duende.IdentityServer.Configuration;

namespace IdentityServer.Configs;

public class CustomIdentityServerOptions
{
    public const string SectionName = "IdentityServer";

    public required DuendeIdentityServerCachingOptions CachingOptions { get; set; }

    public required AuthenticationOptions AuthenticationOptions { get; set; }
}
