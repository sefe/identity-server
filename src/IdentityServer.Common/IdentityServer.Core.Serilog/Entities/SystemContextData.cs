namespace IdentityServer.Core.Serilog.Entities;
public class SystemContextData
{
    public const string Alias = "System";

    public string? Name { get; set; }

    public string? Version { get; set; }

    public string? CoreVersion { get; set; }

    public string? Environment { get; set; }

    public string? EnvironmentTier { get; set; }

    public string? ComponentName { get; set; }

    public string? MachineName { get; set; }

    public string? ProcessUserIdentity { get; set; }
}
