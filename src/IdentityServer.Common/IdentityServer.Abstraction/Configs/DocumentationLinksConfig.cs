namespace IdentityServer.Abstraction.Configs;

public class DocumentationLinksConfig
{
    public const string SectionName = "DocumentationLinks";

    public required string RedirectUriUserGuide { get; set; }
    public required string RedirectUriHttpSecurityWarning { get; set; }
    public required string PostLogoutRedirectUriUserGuide { get; set; }
    public required string PostLogoutRedirectUriHttpSecurityWarning { get; set; }
    public required string GrantTypesUserGuide { get; set; }
    public required string NamingStandardUserGuide { get; set; }
    public required string MainUserGuide { get; set; }
}
