using Microsoft.Extensions.Logging;

namespace IdentityServer.Tests.Common;

public class MockLogger<T> : ILogger<T>
{
    public List<string> CapturedErrors { get; } = new();
    public List<string> CapturedWarnings { get; } = new();
    public List<string> CapturedInfo { get; } = new();

    public void Log<TState>(LogLevel logLevel, EventId eventId, TState state, Exception exception, Func<TState, Exception, string> formatter)
    {
        switch (logLevel)
        {
            case LogLevel.Error:
                CapturedErrors.Add(formatter(state, exception));
                break;
            case LogLevel.Warning:
                CapturedWarnings.Add(formatter(state, exception));
                break;
            case LogLevel.Information:
                CapturedInfo.Add(formatter(state, exception));
                break;
            default:
                // Handle other log levels if needed
                break;
        }
    }

    public bool IsEnabled(LogLevel logLevel) => true;
    public IDisposable BeginScope<TState>(TState state) => null!;
}
