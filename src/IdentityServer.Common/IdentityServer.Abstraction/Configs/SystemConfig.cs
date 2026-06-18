namespace IdentityServer.Abstraction.Configs;

public class SystemConfig : ISystemConfig
{
    public const string SystemSectionName = "System";

    public required bool EnableLoggingDiagnosticsToConsole { get; set; }
    public required bool EnableLoggingDiagnosticsToFile { get; set; }
    public required string LoggingDiagnosticsFile { get; set; }
    public required string Environment { get; set; }
    public required string EnvironmentTier { get; set; }
    public bool IsProd => EnvironmentTier == "PR";
    public required string SystemName { get; set; }
    public required string ApplicationName { get; set; }
    public required string SupportEmailAddress { get; set; }
    public required string SecurityNotice { get; set; }
    public required string SecurityDisclaimerText { get; set; }
    public required LoadBalancerConfig LoadBalancer { get; set; }
}

public class LoadBalancerConfig
{
    public required string IpRange { get; set; }
    public required int Mask { get; set; }
}
