namespace IdentityServer.Abstraction.Configs;

public class MicrosoftEntraConfig : IMicrosoftEntraConfig
{
    public string ClientId { get; set; } = string.Empty;
    public string TenantId { get; set; } = string.Empty;
    public string ClientSecret { get; set; } = string.Empty;
}
