// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

using Duende.IdentityServer;
using Duende.IdentityServer.EntityFramework.Services;
using Duende.IdentityServer.Models;
using Duende.IdentityServer.Stores;
using IdentityServer.Abstraction.Contracts;
using Microsoft.Extensions.Caching.Hybrid;
using Microsoft.Extensions.DependencyInjection;
using DataEntities = Duende.IdentityServer.EntityFramework.Entities;

namespace IdentityServer.Data.Caching;

public sealed class ConfigurationCacheInvalidator<T>(
    [FromKeyedServices(ServiceProviderKeys.ConfigurationStoreCache)] HybridCache cache)
    : IConfigurationCacheInvalidator<T> where T : class
{
    public Task RemoveAsync(string key)
    {
        ArgumentException.ThrowIfNullOrEmpty(key);

        // Duende 8's internal CacheKey.For<T> uses model FullName, not EF entity names.
        var cacheKey = typeof(T) == typeof(DataEntities.Client)
            ? $"IS:{typeof(Client).FullName}-{key}"
            : typeof(T) == typeof(DataEntities.ApiResource) || typeof(T) == typeof(DataEntities.ApiScope)
                ? $"IS:{typeof(Resources).FullName}-__all__"
                : typeof(T) == typeof(CachingCorsPolicyService<CorsPolicyService>.CorsCacheEntry)
                    ? $"IS:{typeof(T).FullName}-{key}"
                    : throw new NotSupportedException($"Configuration invalidation is not defined for {typeof(T)}.");

        return cache.RemoveAsync(cacheKey).AsTask();
    }
}

public sealed class NoOpConfigurationCacheInvalidator<T> : IConfigurationCacheInvalidator<T> where T : class
{
    public Task RemoveAsync(string key) => Task.CompletedTask;
}
