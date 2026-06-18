namespace IdentityServer.AdminPortal.Web.Models;

public class ScopeWrapper<TScope>
{
    public const string OpenIdConnectFakeApiName = "OpenID Connect";

    public ScopeWrapper(TScope scope, string name)
    {
        Scope = scope;
        (NameOfApi, NameOfScope) = SplitScopeName(name);
    }

    public bool IsSelected { get; set; }
    public bool IsAlreadyAdded { get; set; }
    public string NameOfApi { get; set; }
    public string NameOfScope { get; set; }
    public TScope Scope { get; set; }

    private static (string api, string own) SplitScopeName(string s)
    {
        var parts = s.Split('.', 2, StringSplitOptions.RemoveEmptyEntries);
        if (parts.Length == 2)
        {
            return (parts[0], parts[1]);
        }
        else
        {
            return (OpenIdConnectFakeApiName, parts[0]);
        }
    }
}
