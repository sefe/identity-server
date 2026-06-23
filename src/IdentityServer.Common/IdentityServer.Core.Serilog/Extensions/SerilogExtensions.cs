// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.Http;
using Microsoft.Extensions.Configuration;
using Serilog;
using Serilog.Core;
using Serilog.Debugging;
using IdentityServer.Abstraction;
using IdentityServer.Abstraction.Configs;
using IdentityServer.Abstraction.Extensions;
using IdentityServer.Core.Serilog.Entities;
using static IdentityServer.Abstraction.Constants;

namespace IdentityServer.Core.Serilog.Extensions;

public static class SerilogExtensions
{
    public static WebApplicationBuilder ConfigureSerilog(this WebApplicationBuilder builder)
    {
        builder.Logging.AddSerilog();
        builder.Host.UseSerilog(); //use Log.Logger, dispose: true

        return builder;
    }

    public static Logger CreateLogger(IConfiguration configuration)
    {
        LoggerConfiguration loggerConfiguration = new();
        var systemConfig = configuration.GetRequiredSection("System").Get<SystemConfig>() ??
            throw new InvalidOperationException("System details are not configured in appsettings ('System' section).");

        if (systemConfig.EnableLoggingDiagnosticsToConsole)
        {
            SelfLog.Enable(Console.Error);
        }

        if (systemConfig.EnableLoggingDiagnosticsToFile)
        {
            var diagnosticsFilePath = systemConfig.LoggingDiagnosticsFile;
            if (diagnosticsFilePath != null)
            {
                SelfLog.Enable(msg => File.AppendAllText(diagnosticsFilePath, msg));
            }
        }

        loggerConfiguration
            .ReadFrom.Configuration(configuration)
            .Enrich.With(new TradingSerilogEnricher(cfg =>
            {
                cfg.Name = systemConfig.SystemName;
                cfg.ComponentName = systemConfig.ApplicationName;
                cfg.EnvironmentTier = systemConfig.EnvironmentTier;
                cfg.Environment = systemConfig.Environment;
                cfg.Version = CommonHelpers.GetEntryAssemblyVersion();
            }));

        return loggerConfiguration.CreateLogger();
    }

    /// <summary>
    /// Enriches the request logging with standard information and additional information for Duende IdentityServer.
    /// </summary>
    public static WebApplication UseSerilogRequestDuendeLogging(this WebApplication app)
    {
        return app.UseSerilogRequestCustomLogging(ConfigureRequestDuendeLogging);
    }

    public static WebApplication UseSerilogRequestCustomLogging(this WebApplication app, Action<IDiagnosticContext, HttpContext> reqLogging)
    {
        app.UseSerilogRequestLogging(opts =>
        {
            opts.EnrichDiagnosticContext = reqLogging;
        });
        return app;
    }

    public static void ConfigureRequestStandardLogging(this IDiagnosticContext diagnosticContext, HttpContext httpContext)
    {
        diagnosticContext.Set(KnownSerilogPropertyNames.HttpMethod, httpContext.Request.Method);
        diagnosticContext.Set(KnownSerilogPropertyNames.ResponseStatusCode, httpContext.Response.StatusCode);
        diagnosticContext.Set(CustomContextFields.Endpoint, httpContext.Request.Path);
        diagnosticContext.Set(CustomContextFields.SourceIp, httpContext.GetSourceIp());
        diagnosticContext.Set(CustomContextFields.Referer, httpContext.Request.Headers.Referer.FirstOrDefault() ?? "");

        var username = httpContext.User.GetUserNameOrDefault();
        if (!string.IsNullOrEmpty(username))
        {
            diagnosticContext.Set(CustomContextFields.Username, username);
        }
    }

    public static bool TryAddValueFromHttpContext(this IDiagnosticContext diagnosticContext, HttpContext httpContext, string key)
    {
        if (httpContext.Items.TryGetValue(key, out var value) && value != null)
        {
            diagnosticContext.Set(key, value);
            return true;
        }

        return false;
    }

    private static void ConfigureRequestDuendeLogging(IDiagnosticContext diagnosticContext, HttpContext httpContext)
    {
        diagnosticContext.ConfigureRequestStandardLogging(httpContext);

        diagnosticContext.AddValue(httpContext, CustomContextFields.ClientId);
        diagnosticContext.AddValue(httpContext, CustomContextFields.GrantType);
        diagnosticContext.TryAddValueFromHttpContext(httpContext, CustomContextFields.SubjectId);
        diagnosticContext.TryAddValueFromHttpContext(httpContext, CustomContextFields.AuthMethod);
        diagnosticContext.TryAddValueFromHttpContext(httpContext, CustomContextFields.CorrelationId);
    }

    private static void AddValue(this IDiagnosticContext diagnosticContext, HttpContext httpContext, string key)
    {
        var added = diagnosticContext.TryAddValueFromHttpContext(httpContext, key);
        if (added)
        {
            return;
        }

        if (httpContext.Request.Query.TryGetValue(key, out var keyFromQuery))
        {
            diagnosticContext.Set(key, keyFromQuery);
        }
        else if (httpContext.Request.HasFormContentType
                 && httpContext.Request.Form.TryGetValue(key, out var keyFromForm))
        {
            diagnosticContext.Set(key, keyFromForm.ToString());
        }
    }

    private static string GetSourceIp(this HttpContext httpContext)
    {
        return httpContext.Connection.RemoteIpAddress?.MapToIPv4().ToString() ?? "";
    }
}
