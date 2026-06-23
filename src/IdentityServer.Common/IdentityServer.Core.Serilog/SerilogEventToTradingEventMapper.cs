// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

using Elastic.CommonSchema;
using Serilog.Events;
using IdentityServer.Core.Serilog.Entities;
using IdentityServer.Core.Serilog.Extensions;

namespace IdentityServer.Core.Serilog;

public class SerilogEventToTradingEventMapper
{
    private readonly string _applicationName;

    public SerilogEventToTradingEventMapper(string applicationName)
    {
        _applicationName = applicationName;
    }

    public TradingLogEvent Map(LogEvent source)
    {
        TradingLogEvent target = new()
        {
            Timestamp = source.Timestamp,
            Message = source.RenderMessage(),
            Ecs = new Ecs
            {
                Version = Base.Version
            }
        };
        MapException(source, target);
        MapHttpContext(source, target);
        MapContext(source, target, delegate (SystemContextData c)
        {
            if (string.IsNullOrWhiteSpace(c.MachineName))
            {
                c.MachineName = source.GetPropertyOrDefault<string>(KnownSerilogPropertyNames.MachineName) ?? Environment.MachineName;
            }
        });
        MapEvent(source, target);
        MapTrace(source, target);
        MapClient(source, target);
        MapLog(source, target);
        MapAgent(source, target);
        MapHost(source, target);
        MapProcess(source, target);
        MapCustomAppProperties(source, target);
        return target;
    }

    private void MapCustomAppProperties(LogEvent source, TradingLogEvent target)
    {
        if (source.TryGetCustomAppProperties(out IDictionary<string, object> props))
        {
            target.TopLevel = target.TopLevel ?? new CustomProperties();
            target.TopLevel[_applicationName] = props;
        }
    }

    private static void MapException(LogEvent source, TradingLogEvent target)
    {
        if (source.Exception != null)
        {
            target.Error = new Error
            {
                Message = source.Exception.Message,
                Type = source.Exception.GetType().Name,
                StackTrace = source.Exception.StackTrace,
                Code = source.Exception.HResult.ToString()
            };
        }
    }

    private static void MapHttpContext(LogEvent source, TradingLogEvent target)
    {
        if (source.TryGetPropertyFromContext(out ContextDataProperty<HttpContextData>? value) && value != null)
        {
            HttpContextData value2 = value.Value!;
            target.Http = new Http
            {
                Request = new HttpRequest
                {
                    Method = value2.HttpMethod,
                    Referrer = value2.RequestPath
                }
            };
            if (value2.ResponseStatusCode.HasValue)
            {
                target.Http.Response = new HttpResponse
                {
                    StatusCode = value2.ResponseStatusCode.Value
                };
            }

            target.Client = target.Client ?? new Client();
            target.Client.Ip = value2.ClientIpAddress;
            target.TopLevel = target.TopLevel ?? new CustomProperties();
            target.TopLevel[value.Name] = new { value2.Controller, value2.Action };
        }
    }

    private static void MapContext<T>(LogEvent source, TradingLogEvent target, Action<T>? action = null) where T : class, new()
    {
        if (source.TryGetPropertyFromContext(out ContextDataProperty<T>? value) && value != null && value.Value != null)
        {
            action?.Invoke(value.Value);
            target.TopLevel = target.TopLevel ?? new CustomProperties();
            target.TopLevel[value.Name] = value.Value;
        }
    }

    private static void MapAgent(LogEvent source, TradingLogEvent target)
    {
        Assign(KnownSerilogPropertyNames.ApplicationId, (a, v) => a.Id = v);
        Assign(KnownSerilogPropertyNames.ApplicationName, (a, v) => a.Name = v);
        Assign(KnownSerilogPropertyNames.ApplicationType, (a, v) => a.Type = v);
        Assign(KnownSerilogPropertyNames.ApplicationVersion, (a, v) => a.Version = v);
        void Assign(string key, Action<Agent, string> assign)
        {
            if (source.TryGetProperty<string>(key, out var value))
            {
                target.Agent = target.Agent ?? new Agent();
                assign(target.Agent, value);
            }
        }
    }

    private static void MapEvent(LogEvent source, TradingLogEvent target)
    {
        if (source.TryGetProperty<string>(KnownSerilogPropertyNames.RequestId, out var value))
        {
            target.Event = target.Event ?? new Event();
            target.Event.Id = value;
        }
    }

    private static void MapClient(LogEvent source, TradingLogEvent target)
    {
        if (source.TryGetProperty<string>(KnownSerilogPropertyNames.IdentityName, out var value))
        {
            target.Client = target.Client ?? new Client();
            target.Client.User = target.Client.User ?? new User();
            target.Client.User.Name = value;
        }
    }

    private static void MapLog(LogEvent source, TradingLogEvent target)
    {
        target.Log = target.Log ?? new Log();
        target.Log.Level = source.Level.ToString("F");
        if (source.TryGetProperty<string>(KnownSerilogPropertyNames.SourceContext, out var value))
        {
            target.Log.Logger = value;
        }
    }

    private static void MapTrace(LogEvent source, TradingLogEvent target)
    {
        string? text = null;
        if (source.TryGetProperty<Guid>(KnownSerilogPropertyNames.CorrelationId, out var value))
        {
            text = value.ToString();
        }
        else if (source.TryGetProperty(KnownSerilogPropertyNames.CorrelationId, out string value2))
        {
            text = value2;
        }

        if (!string.IsNullOrWhiteSpace(text))
        {
            target.Trace = target.Trace ?? new Trace();
            target.Trace.Id = text;
        }
    }

    private static void MapProcess(LogEvent source, TradingLogEvent logEvent)
    {
        source.TryGetProperty<int>(KnownSerilogPropertyNames.ProcessId, out var value);
        source.TryGetProperty<string>(KnownSerilogPropertyNames.ProcessName, out var value2);
        source.TryGetProperty<int>(KnownSerilogPropertyNames.ThreadId, out var value3);
        source.TryGetProperty<string>(KnownSerilogPropertyNames.ThreadName, out var value4);
        if (value2 != null || value !=0 || value3 !=0 || value4 != null)
        {
            logEvent.Process = logEvent.Process ?? new Process();
            logEvent.Process.Title = string.IsNullOrEmpty(value2) ? null : value2;
            logEvent.Process.Name = value2;
            logEvent.Process.Pid = value;
            logEvent.Process.Thread = logEvent.Process.Thread ?? new ProcessThread();
            logEvent.Process.Thread.Id = value3;
            logEvent.Process.Thread.Name = value4;
        }
    }

    private static void MapHost(LogEvent source, TradingLogEvent target)
    {
        if (source.TryGetProperty<string>(KnownSerilogPropertyNames.MachineName, out var value))
        {
            target.Host = target.Host ?? new Host();
            target.Host.Name = value;
        }
    }
}
