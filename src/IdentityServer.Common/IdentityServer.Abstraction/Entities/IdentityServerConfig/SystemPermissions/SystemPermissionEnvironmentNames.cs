namespace IdentityServer.Abstraction.Entities.IdentityServerConfig.SystemPermissions;

/// <summary>
/// Predefined list of environments in use.
/// If adding new environments, please ensure they are added in the correct order and that they align with standards.
/// Additionally, beware of the 50 characters length limit on the database level.
/// </summary>
public static class SystemPermissionEnvironmentNames
{
    public static readonly IReadOnlyDictionary<string, int> OrderedEnvironments = new Dictionary<string, int> {
        { Development, 10 },
        { QA, 20 },
        { Integration, 30 },
        { Testing, 40 },
        { Staging, 50 },
        { PreProduction, 60 },
        { FixOnFail, 70 },
        { Production, 80 },
    };

    public static readonly IReadOnlyList<string> OrderedEnvironmentNames = new List<string> {
        Development,
        QA,
        Integration,
        Testing,
        Staging,
        PreProduction,
        FixOnFail,
        Production,
    };

    public static readonly IReadOnlySet<string> EnvironmentNames = new HashSet<string>(OrderedEnvironmentNames, StringComparer.Ordinal);

    public const string Development = "Development";
    public const string QA = "QA";
    public const string Testing = "UAT";
    public const string Staging = "Staging";
    public const string Integration = "Integration";
    public const string PreProduction = "Pre Production";
    public const string FixOnFail = "Fix on Fail";
    public const string Production = "Production";
}
