namespace IdentityServer.Abstraction.Entities;

public class HealthStatus
{
    public const string Healthy = "Healthy";

    public string Status { get; }
    public DateTime Timestamp { get; }

    public HealthStatus(string status)
        : this(status, DateTime.UtcNow)
    {
    }

    public HealthStatus(string status, DateTime timestamp)
    {
        Status = status;
        Timestamp = timestamp;
    }

    public override bool Equals(object? obj)
    {
        return obj is HealthStatus other &&
               Status == other.Status &&
               Timestamp == other.Timestamp;
    }

    public override int GetHashCode()
    {
        return HashCode.Combine(Status, Timestamp);
    }
}