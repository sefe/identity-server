namespace IdentityServer.Services;

public class AuthSchemeIssuerMapping
{
    public Dictionary<string, string> IssuerToSchemeMap { get; } = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
}
