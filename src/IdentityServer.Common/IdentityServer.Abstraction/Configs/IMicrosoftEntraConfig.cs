namespace IdentityServer.Abstraction.Configs;

public interface IMicrosoftEntraConfig
{
    string ClientId { get; }
    string TenantId { get; }
    string ClientSecret { get; }
}
