// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

using Microsoft.Extensions.DependencyInjection;
using Microsoft.Identity.Client;
using Polly;
using System.Diagnostics.CodeAnalysis;
using IdentityServer.Abstraction.Configs;
using IdentityServer.Abstraction.Contracts.MicrosoftGraph;
using IdentityServer.Core.Extensions;
using IdentityServer.MicrosoftGraph.Caching;

namespace IdentityServer.MicrosoftGraph.Extensions;

[ExcludeFromCodeCoverage]
public static class MicrosoftGraphExtensions
{
    public static IServiceCollection AddMicrosoftGraphAuth(this IServiceCollection services, IMicrosoftEntraConfig entraConfig)
    {
        var confidentialClient = ConfidentialClientApplicationBuilder.Create(entraConfig.ClientId)
            .WithClientSecret(entraConfig.ClientSecret)
            .WithAuthority(new Uri($"https://login.microsoftonline.com/{entraConfig.TenantId}"))
            .Build();

        services.AddSingleton(confidentialClient);
        services.AddTransient<MicrosoftGraphAuthHandler>();

        return services;
    }

    public static IServiceCollection AddMicrosoftGraphApplicationClient(this IServiceCollection services, IHttpRetryPolicyConfig retryPolicyConfig)
    {
        services.AddGraphHttpClient<MicrosoftGraphApplicationApiClient>(Constants.HttpClientNames.GraphApplicationsClientName, retryPolicyConfig);

        services.AddScoped<IMicrosoftGraphApplicationApi, MicrosoftGraphApplicationApiClient>();
        services.AddScoped<IEntraApplicationService, EntraApplicationService>();

        return services;
    }

    public static IServiceCollection AddMicrosoftGraphGroupClient(this IServiceCollection services, IHttpRetryPolicyConfig retryPolicyConfig)
    {
        services.AddGraphHttpClient<MicrosoftGraphGroupApiClient>(Constants.HttpClientNames.GraphGroupsClientName, retryPolicyConfig);

        services.AddScoped<IMicrosoftGraphGroupApi, MicrosoftGraphGroupApiClient>();
        services.AddScoped<IEntraGroupService, EntraGroupService>();

        return services;
    }

    public static IServiceCollection AddMicrosoftGraphUserClient(this IServiceCollection services, IHttpRetryPolicyConfig retryPolicyConfig)
    {
        services.AddGraphHttpClient<MicrosoftGraphUserApiClient>(Constants.HttpClientNames.GraphUsersClientName, retryPolicyConfig);

        services.AddScoped<IMicrosoftGraphUserApi, MicrosoftGraphUserApiClient>();
        services.AddScoped<IEntraUserService, EntraUserService>();

        return services;
    }

    public static IServiceCollection AddCaching(this IServiceCollection services, IMicrosoftEntraCacheConfig cacheConfig)
    {
        if (cacheConfig.Enabled)
        {
            services.Decorate<IEntraApplicationService, EntraApplicationCachedService>();
            services.Decorate<IEntraGroupService, EntraGroupCachedService>();
            services.Decorate<IEntraUserService, EntraUserCachedService>();
        }

        return services;
    }

    private static IServiceCollection AddGraphHttpClient<T>(this IServiceCollection services, string clientName, IHttpRetryPolicyConfig retryPolicyConfig)
    {
        services.AddHttpClient(clientName, client =>
        {
            client.BaseAddress = Constants.MicrosoftGraphUri;
            client.DefaultRequestHeaders.Add("ConsistencyLevel", "eventual");
        })
        .AddHttpMessageHandler<MicrosoftGraphAuthHandler>()
        .AddStandardResilienceHandler(options =>
        {
            options.Retry.MaxRetryAttempts = retryPolicyConfig.RetryCount;
            options.Retry.Delay = TimeSpan.FromSeconds(retryPolicyConfig.GrowthFactorInSeconds);
            options.Retry.BackoffType = DelayBackoffType.Exponential;
            options.Retry.UseJitter = true;

            options.Retry.OnRetry = (args) =>
            {
                var response = args.Outcome.Result;

                var exc = args.Outcome.Exception;

                Serilog.Log.ForContext<T>()
                    .Warning(exc, "Request to Microsoft Graph API failed with {StatusCode} code. Retrying request in {RetryDelay}. Attempt {AttemptNumber} of {MaxRetryAttempts}.",
                    response?.StatusCode, args.RetryDelay, args.AttemptNumber, retryPolicyConfig.RetryCount);

                return ValueTask.CompletedTask;
            };
        });

        return services;
    }
}
