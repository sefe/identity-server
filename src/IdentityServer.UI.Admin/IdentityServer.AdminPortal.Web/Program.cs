// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

using Microsoft.AspNetCore.Components.Web;
using Microsoft.AspNetCore.Components.WebAssembly.Authentication;
using Microsoft.AspNetCore.Components.WebAssembly.Hosting;
using Serilog;
using IdentityServer.Abstraction.Configs;
using IdentityServer.Abstraction.DTO.ApiResources;
using IdentityServer.Abstraction.DTO.Clients;
using IdentityServer.Abstraction.DTO.SystemPermissions;
using IdentityServer.Abstraction.Entities.EntraEntities;
using IdentityServer.AdminPortal.Web;
using IdentityServer.AdminPortal.Web.Components.Interop;
using IdentityServer.AdminPortal.Web.Models;
using IdentityServer.AdminPortal.Web.Services;
using IdentityServer.AdminPortal.Web.Services.History;
using IdentityServer.AdminPortal.Web.Services.Search;
using IdentityServer.AdminPortal.Web.Services.Storage;

var builder = WebAssemblyHostBuilder.CreateDefault(args);

Log.Logger = new LoggerConfiguration()
    .WriteTo.BrowserConsole()
    .CreateLogger();

builder.RootComponents.Add<App>("#app");
builder.RootComponents.Add<HeadOutlet>("head::after");

try
{
    builder.Services.AddOptions<FeatureOptions>().Bind(builder.Configuration.GetSection(FeatureOptions.Features));
    builder.Services.AddOptions<IdentityServerCachingOptions>().Bind(builder.Configuration.GetSection("IdentityServer:CachingOptions"));
    builder.Services.AddOptions<SecretExpirationConfig>().Bind(builder.Configuration.GetSection(SecretExpirationConfig.SectionName));

    // Register storage services with interface
    builder.Services.AddSingleton<SessionStorageService>();
    builder.Services.AddSingleton<IJSStorageService, LocalStorageService>();

    builder.Services.AddSingleton<UserRoleFilteringService>();

    builder.Services.AddScoped<IClipboardService, ClipboardService>();

    builder.Services.AddScoped<IThemeService, ThemeService>();

    // https://learn.microsoft.com/en-us/aspnet/core/blazor/security/webassembly/additional-scenarios?view=aspnetcore-8.0#attach-tokens-to-outgoing-requests
    builder.Services.AddHttpClient(AdminApiService.HttpClientName, client => client.BaseAddress = new Uri(builder.HostEnvironment.BaseAddress))
        .AddHttpMessageHandler<BaseAddressAuthorizationMessageHandler>();

    builder.Services.AddScoped<IAdminApiService, AdminApiService>();

    // History undo services - entity-specific implementations
    builder.Services.AddScoped<IEntityHistoryUndoService<ClientDtoRead>, ClientHistoryUndoService>();
    builder.Services.AddScoped<IEntityHistoryUndoService<ApiResourceDtoRead>, ApiResourceHistoryUndoService>();
    builder.Services.AddScoped<IEntityHistoryUndoService<SystemPermissionDtoRead>, SystemPermissionHistoryUndoService>();
    builder.Services.AddScoped<IHistoryUndoService, HistoryUndoService>();

    builder.Services.AddScoped<ISearchProvider<ClientShortDtoRead>, ClientProvider>();
    builder.Services.AddScoped<ISearchProvider<Group>, EntraGroupSearchProvider>();
    builder.Services.AddScoped<ISearchProvider<User>, EntraUserSearchProvider>();
    builder.Services.AddScoped<ISystemOwnerService, SystemOwnerService>();

    builder.Services.AddTelerikBlazor();
    builder.Services.AddScoped<NotificationService>();
    builder.Services.AddSingleton<IConfirmationService, ConfirmationService>();

    var systemConfig = builder.Configuration
                .GetRequiredSection(SystemConfig.SystemSectionName)
                .Get<SystemConfig>()!;
    builder.Services.AddSingleton<ISystemConfig>(systemConfig);

    builder.Services.AddOidcAuthentication(options =>
    {
        options.UserOptions.RoleClaim = "role";

        // Configure your authentication provider options here.
        // For more information, see https://aka.ms/blazor-standalone-auth
        builder.Configuration.Bind("IdentityServer", options.ProviderOptions);

        if (string.IsNullOrEmpty(options.ProviderOptions.PostLogoutRedirectUri))
        {
            options.ProviderOptions.PostLogoutRedirectUri = builder.HostEnvironment.BaseAddress + "bye";
        }
    }).AddAccountClaimsPrincipalFactory<RemoteAuthenticationState, RemoteUserAccount, ExtendedUserAccountFactory>();

    await builder.Build().RunAsync();
}
catch (Exception ex)
{
    Log.Fatal(ex, "Unhandled exception");
}
finally
{
    await Log.CloseAndFlushAsync();
}
