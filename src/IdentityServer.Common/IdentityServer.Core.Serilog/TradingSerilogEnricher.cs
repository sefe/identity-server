using Serilog.Core;
using Serilog.Events;
using System.Reflection;
using IdentityServer.Core.Serilog.Entities;
using IdentityServer.Core.Serilog.Extensions;

namespace IdentityServer.Core.Serilog;

public class TradingSerilogEnricher : ILogEventEnricher
{
    private static readonly Version _appVersion = (Assembly.GetEntryAssembly() ?? Assembly.GetCallingAssembly()).GetName().Version!;
    private static readonly Version _coreVersion = Assembly.GetExecutingAssembly().GetName().Version!;
    private readonly SystemContextData _context;

    public TradingSerilogEnricher(Action<SystemContextData> configuration)
    {
        _context = new SystemContextData()
        {
            Version = _appVersion.ToString(),
            CoreVersion = _coreVersion.ToString(),
            ProcessUserIdentity = Environment.UserName
        };
        
        configuration?.Invoke(this._context);
    }

    public void Enrich(LogEvent logEvent, ILogEventPropertyFactory propertyFactory)
    {
        foreach (KeyValuePair<string, object> keyValuePair in _context.DeconstructToContextPropertiesWithPrefix<SystemContextData>(alias: "System")
            .Where(x => x.Value != null)
            .ToList())
        {
            logEvent.AddPropertyIfAbsent(new LogEventProperty(keyValuePair.Key, (LogEventPropertyValue)new ScalarValue(keyValuePair.Value)));
        }
    }
}
