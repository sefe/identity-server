// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

using Duende.IdentityServer;
using IdentityServer.Abstraction.Configs;
using IdentityServer.Abstraction.Contracts;
using Microsoft.Extensions.Caching.Distributed;
using Microsoft.Extensions.Caching.Hybrid;
using Microsoft.Extensions.Caching.StackExchangeRedis;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Options;
using StackExchange.Redis;

namespace IdentityServer.Data.Caching;

public static class ConfigurationCacheServiceCollectionExtensions
{
    internal const string SharedCacheKey = "IdentityServer.SharedConfiguration";

    public static IServiceCollection AddSharedConfigurationCache(this IServiceCollection services)
    {
        services.AddKeyedSingleton<IDistributedCache>(SharedCacheKey, (provider, _) =>
            new Microsoft.Extensions.Caching.StackExchangeRedis.RedisCache(Options.Create(new RedisCacheOptions
            {
                InstanceName = $"{provider.GetRequiredService<ISystemConfig>().Environment}:configuration:v8:",
                ConnectionMultiplexerFactory = () => Task.FromResult(provider.GetRequiredService<IConnectionMultiplexer>())
            })));
        services.AddKeyedHybridCache(SharedCacheKey, options =>
        {
            options.DistributedCacheServiceKey = SharedCacheKey;
        });
        services.AddKeyedSingleton<HybridCache>(ServiceProviderKeys.ConfigurationStoreCache,
            (provider, _) => new SharedConfigurationCache(provider.GetRequiredKeyedService<HybridCache>(SharedCacheKey)));
        services.AddSingleton(typeof(IConfigurationCacheInvalidator<>), typeof(ConfigurationCacheInvalidator<>));
        return services;
    }
}
