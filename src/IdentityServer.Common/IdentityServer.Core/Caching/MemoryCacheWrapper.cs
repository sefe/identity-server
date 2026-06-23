// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

using Microsoft.Extensions.Caching.Memory;
using IdentityServer.Abstraction.Contracts;
using IdentityServer.Abstraction.Extensions;

namespace IdentityServer.Core.Caching;

public class MemoryCacheWrapper<T> : ICache<T> where T : class
{
    private readonly IMemoryCache _memoryCache;
    private readonly string _keyPrefix;

    public MemoryCacheWrapper(IMemoryCache memoryCache)
    {
        _memoryCache = memoryCache;
        var cacheTypeName = typeof(T).GetTypeDisplayName();
        _keyPrefix = cacheTypeName + ":";
    }

    public Task<T?> GetAsync(string key)
    {
        key = NormalizeKey(key);
        if (_memoryCache.TryGetValue(key, out T? value))
        {
            return Task.FromResult(value);
        }
        return Task.FromResult<T?>(default);
    }

    public Task<Dictionary<string, T?>> GetManyAsync(IEnumerable<string> keys)
    {
        var result = new Dictionary<string, T?>();
        foreach (var key in keys.Distinct())
        {
            var normalizedKey = NormalizeKey(key);
            if (_memoryCache.TryGetValue(normalizedKey, out T? value))
            {
                result[key] = value;
            }
            else
            {
                result[key] = default;
            }
        }
        return Task.FromResult(result);
    }

    public async Task<T> GetOrAddAsync(string key, TimeSpan duration, Func<Task<T>> get)
    {
        key = NormalizeKey(key);
        if (_memoryCache.TryGetValue(key, out T? value) && value != null)
        {
            return value;
        }

        var newValue = await get();
        _memoryCache.Set(key, newValue, duration);
        return newValue;
    }

    public Task SetAsync(string key, T item, TimeSpan expiration)
    {
        key = NormalizeKey(key);
        _memoryCache.Set(key, item, expiration);
        return Task.CompletedTask;
    }

    public Task SetManyAsync(Dictionary<string, T> items, TimeSpan expiration)
    {
        foreach (var item in items)
        {
            var normalizedKey = NormalizeKey(item.Key);
            _memoryCache.Set(normalizedKey, item.Value, expiration);
        }
        return Task.CompletedTask;
    }

    public Task RemoveAsync(string key)
    {
        key = NormalizeKey(key);
        _memoryCache.Remove(key);
        return Task.CompletedTask;
    }

    internal string NormalizeKey(string key)
    {
        return (_keyPrefix + key).ToLowerInvariant();
    }
}
