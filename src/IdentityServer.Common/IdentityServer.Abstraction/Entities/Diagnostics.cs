namespace IdentityServer.Abstraction.Entities;

public class Diagnostics
{
    public required ICollection<LogDocument> Logs { get; set; }
    public required DiagnosticMetrics Metrics { get; set; }
}