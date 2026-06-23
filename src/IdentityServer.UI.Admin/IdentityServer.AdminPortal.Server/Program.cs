// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

using System.Reflection;
using Microsoft.Extensions.Hosting.WindowsServices;
using Serilog;
using IdentityServer.AdminPortal.Server;
using IdentityServer.Core.Extensions;
using IdentityServer.Core.Serilog.Extensions;
using IdentityServer.OnePassword.Extensions;

Log.Logger = new LoggerConfiguration().WriteTo.Console().CreateBootstrapLogger();
Log.Information("Starting {ApplicationName}", "Trading IdentityServer Admin Portal");

try
{
    var options = new WebApplicationOptions
    {
        Args = args,
        ContentRootPath = WindowsServiceHelpers.IsWindowsService() ? AppContext.BaseDirectory : default
    };

    var builder = WebApplication.CreateBuilder(options);
    builder.Host.UseWindowsService();

    // Order is important as configuration sources added later override the values supplied by the previous configuration sources.
    var env = builder.Configuration.AddEnvironmentConfiguration();
    builder.Configuration.AddUserSecrets(Assembly.GetExecutingAssembly());

    // Build Serilog with final config based on the app configuration as loaded above (e.g., appsettings.json, environment variables)
    Log.Logger = SerilogExtensions.CreateLogger(builder.Configuration);
    Log.Information("Environment: {0}", env);

    builder.ConfigureSerilog();

    // Inject Entra Secret configuration from 1Password, once Serilog Logger is fully configured such that any errors during this process will be logged.
    // NB! do not change the order of this call, it must be after Serilog is configured but before any services depending on Entra configuration are added.
    builder.Configuration.AddOnePasswordSecrets();

    var app = builder
        .ConfigureServices(env)
        .ConfigurePipeline();

    app.MapHealthChecks("/health");

    await app.RunAsync();
}
catch (HostAbortedException)
{
    // This is a known exception that can occur when running entity framework migrations:
    // https://github.com/dotnet/efcore/issues/29809
}
catch (Exception ex)
{
    Log.Fatal(ex, "Unhandled exception");
}
finally
{
    Log.Information("Shut down complete");
    await Log.CloseAndFlushAsync();
}
