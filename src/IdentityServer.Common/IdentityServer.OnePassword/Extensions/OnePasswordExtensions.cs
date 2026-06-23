// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

using System.Diagnostics.CodeAnalysis;
using System.Net;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Http.Resilience;
using Polly;
using Polly.Timeout;
using IdentityServer.Abstraction.Exceptions;
using IdentityServer.Core.Extensions;

namespace IdentityServer.OnePassword.Extensions;

[ExcludeFromCodeCoverage]
public static class OnePasswordExtensions
{
    private const string _1pSectionName = "OnePassword";

    /// <summary>
    /// Inject secrets from 1Password into the configuration.
    /// </summary>
    /// <param name="builder"></param>
    /// <returns></returns>
    /// <exception cref="IdentityServerException">if any retrieved secret value is empty</exception>
    public static IConfigurationBuilder AddOnePasswordSecrets(this IConfigurationBuilder builder)
    {
        var existingConfig = builder.Build();
        var onePasswordConfig = existingConfig.DirectGetSection<OnePasswordConfig>(_1pSectionName);
        RemoveAlreadyPresentConfigEntries(existingConfig, onePasswordConfig);

        if (onePasswordConfig.Secrets == null || onePasswordConfig.Secrets.Count == 0)
        {
            return builder;
        }

        using var httpClient = GetResilientHttpClient(existingConfig);
        var client = GetOnePasswordClient(existingConfig, httpClient);

        var secretsDict = RetrieveSecrets(client, onePasswordConfig);

        return builder.AddInMemoryCollection(secretsDict);
    }

    internal static void RemoveAlreadyPresentConfigEntries(IConfigurationRoot existingConfig, OnePasswordConfig onePasswordConfig)
    {
        if (onePasswordConfig.Secrets == null || onePasswordConfig.Secrets.Count == 0)
        {
            return;
        }

        // Only retrieve from 1Pass the configured keys if the current configuration entry for that key is empty.
        // This allows user secrets to provide all necessary values for local development.
        var keysToRemove = onePasswordConfig.Secrets
            .Where(kvp => !string.IsNullOrEmpty(existingConfig[NormalizeConfigKeyName(kvp)]))
            .Select(kvp => kvp.Key)
            .ToList();

        foreach (var key in keysToRemove)
        {
            onePasswordConfig.Secrets.Remove(key);
        }
    }

    private static string NormalizeConfigKeyName(KeyValuePair<string, string> kvp)
    {
        return kvp.Key.Replace("__", ":");
    }

    private static Dictionary<string, string?> RetrieveSecrets(OnePasswordClient client, OnePasswordConfig onePasswordConfig)
    {
        var secretsDict = new Dictionary<string, string?>();
        foreach (var kvp in onePasswordConfig.Secrets)
        {
            var secretValue = client.GetSecretValueAsync(kvp.Value).GetAwaiter().GetResult()
                ?? throw new IdentityServerException($"Value of '{kvp.Value}' item from 1Password '{onePasswordConfig.BaseUrl}' vault '{onePasswordConfig.VaultId}' is empty.");
            secretsDict[NormalizeConfigKeyName(kvp)] = secretValue;
        }
        return secretsDict;
    }

    private static HttpClient GetResilientHttpClient(IConfigurationRoot existingConfig)
    {
        var pipeline = BuildResiliencePipeline(existingConfig);

        var handler = new ResilienceHandler(pipeline)
        {
            InnerHandler = new SocketsHttpHandler()
        };

        var resilientClient = new HttpClient(handler) { Timeout = Timeout.InfiniteTimeSpan };
        return resilientClient;
    }

    private static OnePasswordClient GetOnePasswordClient(IConfigurationRoot existingConfig, HttpClient httpClient)
    {
        var onePasswordConfig = existingConfig.DirectGetSection<OnePasswordConfig>(_1pSectionName);
        var client = new OnePasswordClient(httpClient, onePasswordConfig);
        return client;
    }

    private static ResiliencePipeline<HttpResponseMessage> BuildResiliencePipeline(IConfiguration configuration)
    {
        var httpRetryPolicyConfig = configuration.GetHttpRetryPolicy();

        var builder = new ResiliencePipelineBuilder<HttpResponseMessage>();
        builder.AddRetry(new HttpRetryStrategyOptions
        {
            MaxRetryAttempts = httpRetryPolicyConfig.RetryCount,
            Delay = TimeSpan.FromSeconds(httpRetryPolicyConfig.GrowthFactorInSeconds),
            BackoffType = DelayBackoffType.Exponential,
            ShouldHandle = args => ValueTask.FromResult(
                args.Outcome.Exception is HttpRequestException ||
                args.Outcome.Exception is TimeoutRejectedException ||   // Polly timeout
                args.Outcome.Exception is TaskCanceledException ||       // client-side cancellation
                (args.Outcome.Result is HttpResponseMessage response &&
                 ((int)response.StatusCode >= 500 || response.StatusCode is HttpStatusCode.RequestTimeout or HttpStatusCode.TooManyRequests)) // 5xx or 408 or 429
            ),
            OnRetry = (args) =>
            {
                var retryAttempt = args.AttemptNumber;
                var timespan = args.RetryDelay;
                var outcome = args.Outcome;

                Serilog.Log.Warning(outcome.Exception, "Retrying request to 1Password. Attempt {RetryAttempt} after {Delay} seconds. Error: {Error}",
                    retryAttempt, timespan.TotalSeconds, outcome.Exception?.Message);
                return ValueTask.CompletedTask;
            }
        });
        builder.AddTimeout(TimeSpan.FromSeconds(httpRetryPolicyConfig.DefaultTimeoutInSeconds)); // per-try timeout
        return builder.Build();
    }
}
