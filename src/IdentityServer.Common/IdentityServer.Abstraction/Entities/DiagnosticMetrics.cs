namespace IdentityServer.Abstraction.Entities;

public class DiagnosticMetrics
{
    public int DailyAverageErrors { get; set; }
    public int TotalErrorsLastHour { get; set; }
    public int TotalErrorsLastDay { get; set; }
    public int MetricUpperBound { get; set; }
}