// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

namespace IdentityServer.Core.Serilog.Entities;
public static class KnownSerilogPropertyNames
{
    public const string SourceContext = "SourceContext";

    public const string Host = "Host";

    public const string CorrelationId = "CorrelationId";

    public const string ActionCategory = "ActionCategory";

    public const string ActionName = "ActionName";

    public const string ActionId = "ActionId";

    public const string ActionKind = "ActionKind";

    public const string ActionSeverity = "ActionSeverity";

    public const string ApplicationId = "ApplicationId";

    public const string ApplicationName = "ApplicationName";

    public const string ApplicationType = "ApplicationType";

    public const string ApplicationVersion = "ApplicationVersion";

    public const string ProcessId = "ProcessId";

    public const string ProcessName = "ProcessName";

    public const string ThreadId = "ThreadId";

    public const string ThreadName = "ThreadName";

    public const string MachineName = "MachineName";

    public const string EnvironmentUserName = "EnvironmentUserName";

    public const string IdentityName = "IdentityName";

    public const string RequestId = "RequestId";

    public const string SpanId = "SpanId";

    public const string TraceId = "TraceId";

    public const string ParentId = "ParentId";

    public const string HttpMethod = "HttpMethod";

    public const string ResponseStatusCode = "ResponseStatusCode";

    public const string ClientIpAddress = "ClientIpAddress";

    public const string RequestPath = "RequestPath";

    public static string[] All { get; }

    static KnownSerilogPropertyNames()
    {
        All = (from x in typeof(KnownSerilogPropertyNames).GetFields()
               select x.Name).ToArray();
    }
}
