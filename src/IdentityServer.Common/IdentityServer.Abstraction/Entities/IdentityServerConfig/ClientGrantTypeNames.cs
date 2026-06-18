namespace IdentityServer.Abstraction.Entities.IdentityServerConfig;

public static class ClientGrantTypeNames
{
    public static readonly IReadOnlyDictionary<string, string> AllGrantTypes = new Dictionary<string, string>()
    {
        [Grant_Code] = "Authorization Code",
        [Grant_ClientCredentials] = "Client Credentials",
        [Grant_Hybrid] = "Hybrid",
        [Grant_Implicit] = "Implicit",
        [Grant_Password] = "Resource owner password",
        [Grant_Device] = "Device flow",
        [Grant_TokenExchange] = "Token Exchange",
        [Grant_Ciba] = "Ciba",
    };

    public static readonly IReadOnlySet<string> AllowedGrantsIds = new HashSet<string> {
        Grant_Code,
        Grant_ClientCredentials,
        Grant_Hybrid,
        Grant_Implicit,
        Grant_TokenExchange,
    };

    public static readonly IReadOnlyDictionary<string, string> AllowedGrantTypes = AllGrantTypes.Where(kv => AllowedGrantsIds.Contains(kv.Key)).ToDictionary();

    public static readonly IReadOnlyList<KeyValuePair<string, string>> IncompatibleGrantPairs = new List<KeyValuePair<string, string>>()
    {
        new (Grant_Implicit, Grant_Code),
        new (Grant_Implicit, Grant_Hybrid),
        new (Grant_Code, Grant_Hybrid)
    };

    public const string Grant_Code = "authorization_code";
    public const string Grant_ClientCredentials = "client_credentials";
    public const string Grant_Hybrid = "hybrid";
    public const string Grant_Implicit = "implicit";
    public const string Grant_Password = "password";
    public const string Grant_Device = "urn:ietf:params:oauth:grant-type:device_code";
    public const string Grant_TokenExchange = "urn:ietf:params:oauth:grant-type:token-exchange";
    public const string Grant_Ciba = "urn:openid:params:grant-type:ciba";

    public static bool IsGrantCompatible(string grantKey, IEnumerable<string> selected)
    {
        foreach (var (g1, g2) in IncompatibleGrantPairs)
        {
            if ((grantKey == g1 && selected.Contains(g2)) ||
                (grantKey == g2 && selected.Contains(g1)))
            {
                return false;
            }
        }

        return true;
    }

    public static List<string> GetIncompatibleGrantTypes(string grantKey, IEnumerable<string> selected)
    {
        var incompatibleGrants = new List<string>();
        foreach (var (g1, g2) in IncompatibleGrantPairs)
        {
            if (grantKey == g1 && selected.Contains(g2))
            {
                incompatibleGrants.Add(g2);
            }
            else if (grantKey == g2 && selected.Contains(g1))
            {
                incompatibleGrants.Add(g1);
            }
        }

        return incompatibleGrants;
    }
}
