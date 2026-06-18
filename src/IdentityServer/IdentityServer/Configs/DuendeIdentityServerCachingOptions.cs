using Duende.IdentityServer.Configuration;
using IdentityServer.Abstraction.Configs;

namespace IdentityServer.Configs;

public class DuendeIdentityServerCachingOptions : IdentityServerCachingOptions
{
    public CachingOptions Duende { get; set; } = new();
}
