namespace IdentityServer.Abstraction.Configs;

public interface ISystemConfig
{
    bool EnableLoggingDiagnosticsToConsole { get; }
    bool EnableLoggingDiagnosticsToFile { get; }
    string LoggingDiagnosticsFile { get; }
    string Environment { get; }
    string EnvironmentTier { get; }
    bool IsProd { get; }
    string SystemName { get; }
    string ApplicationName { get; }
    string SupportEmailAddress { get; }
    string SecurityNotice { get; }
    string SecurityDisclaimerText { get; }
}
