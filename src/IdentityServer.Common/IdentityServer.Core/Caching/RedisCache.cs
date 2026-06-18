using Microsoft.Extensions.Logging;
using StackExchange.Redis;
using System.Diagnostics;
using System.Text.Json;
using System.Text.Json.Serialization;
using IdentityServer.Abstraction;
using IdentityServer.Abstraction.Configs;
using IdentityServer.Abstraction.Contracts;
using IdentityServer.Abstraction.Extensions;

namespace IdentityServer.Core.Caching;

/// <summary>
/// Redis-based cache implementation signature-compatible with ICache of Duende Identity Server.
/// </summary>
/// <typeparam name="T">The type of data to cache.</typeparam>
public class RedisCache<T> : ICache<T> where T : class
{
    private readonly JsonSerializerOptions _jsonOptions;
    private readonly IDatabase _database;
    private readonly string _keyPrefix;
    private readonly string _cacheTypeName;
    private readonly ILogger _logger;

    public RedisCache(IConnectionMultiplexer connectionMultiplexer, ISystemConfig systemConfig, ILogger<RedisCache<T>> logger)
    {
        ArgumentNullException.ThrowIfNull(connectionMultiplexer);
        ArgumentNullException.ThrowIfNull(systemConfig);
        ArgumentNullException.ThrowIfNull(logger);

        _database = connectionMultiplexer.GetDatabase();
        _cacheTypeName = typeof(T).GetTypeDisplayName();
        _keyPrefix = systemConfig.Environment + ":" + _cacheTypeName + ":";
        _logger = logger;
        _jsonOptions = new()
        {
            PropertyNameCaseInsensitive = true,
            WriteIndented = false,
            ReferenceHandler = ReferenceHandler.IgnoreCycles
        };
    }

    /// <inheritdoc/>
    public async Task<T?> GetAsync(string key)
    {
        ArgumentException.ThrowIfNullOrEmpty(key);

        var startTimestamp = Stopwatch.GetTimestamp();
        var normalizedKey = NormalizeKey(key);

        try
        {
            var (item, _) = await TryGetFromCacheAsync(normalizedKey, nameof(GetAsync), startTimestamp);

            return item;
        }
        catch (Exception ex)
        {
            var elapsedMs = CommonHelpers.GetElapsedMilliseconds(startTimestamp);
            _logger.CacheOperationError(nameof(GetAsync), _cacheTypeName, normalizedKey, elapsedMs, ex);
            return null!;
        }
    }

    /// <inheritdoc/>
    public async Task<Dictionary<string, T?>> GetManyAsync(IEnumerable<string> keys)
    {
        ArgumentNullException.ThrowIfNull(keys);

        var keyList = keys.ToList();
        if (keyList.Count == 0)
        {
            return new Dictionary<string, T?>();
        }

        var startTimestamp = Stopwatch.GetTimestamp();
        var result = new Dictionary<string, T?>();

        try
        {
            // Normalize all keys
            var normalizedKeys = keyList.Select(NormalizeKey).ToArray();
            var redisKeys = normalizedKeys.Select(k => (RedisKey)k).ToArray();

            // Single batch GET operation (MGET command in Redis)
            var values = await _database.StringGetAsync(redisKeys);

            for (int i = 0; i < keyList.Count; i++)
            {
                var originalKey = keyList[i];
                var normalizedKey = normalizedKeys[i];
                var value = values[i];

                result[originalKey] = PopulateResultFromCache(normalizedKey, value);
            }

            var elapsedMs = CommonHelpers.GetElapsedMilliseconds(startTimestamp);
            _logger.LogInformation("Batch cache GET completed for {Count} {CacheType} keys in {ElapsedMs}ms",
              keyList.Count, _cacheTypeName, elapsedMs);

            return result;
        }
        catch (Exception ex)
        {
            var elapsedMs = CommonHelpers.GetElapsedMilliseconds(startTimestamp);
            _logger.LogError(ex, "Batch cache GET failed for {Count} {CacheType} keys in {ElapsedMs}ms",
              keyList.Count, _cacheTypeName, elapsedMs);

            // Return empty dictionary on error
            foreach (var key in keyList)
            {
                result[key] = null;
            }
            return result;
        }
    }

    /// <inheritdoc/>
    public async Task<T> GetOrAddAsync(string key, TimeSpan duration, Func<Task<T>> get)
    {
        ArgumentException.ThrowIfNullOrEmpty(key);
        ArgumentNullException.ThrowIfNull(get);

        var startTimestamp = Stopwatch.GetTimestamp();
        var normalizedKey = NormalizeKey(key);

        try
        {
            var (cachedItem, foundInCache) = await TryGetFromCacheAsync(normalizedKey, nameof(GetOrAddAsync), startTimestamp);
            if (foundInCache && cachedItem != null)
            {
                return cachedItem;
            }

            var loadStartTimestamp = Stopwatch.GetTimestamp();
            T? item;
            try
            {
                item = await get();
                var loadElapsedMs = CommonHelpers.GetElapsedMilliseconds(loadStartTimestamp);
                _logger.ObjectLoaded(_cacheTypeName, normalizedKey, loadElapsedMs);
            }
            catch (Exception ex)
            {
                var loadElapsedMs = CommonHelpers.GetElapsedMilliseconds(loadStartTimestamp);
                _logger.ObjectLoadFailed(_cacheTypeName, normalizedKey, loadElapsedMs, ex);
                return null!;
            }

            if (item != null)
            {
                await SetAsync(key, item, duration);
            }

            return item!;
        }
        catch (Exception ex)
        {
            var elapsedMs = CommonHelpers.GetElapsedMilliseconds(startTimestamp);
            _logger.CacheOperationError(nameof(GetOrAddAsync), _cacheTypeName, normalizedKey, elapsedMs, ex);
            return null!;
        }
    }

    /// <inheritdoc/>
    public async Task SetAsync(string key, T item, TimeSpan expiration)
    {
        ArgumentException.ThrowIfNullOrEmpty(key);
        ArgumentNullException.ThrowIfNull(item);

        var startTimestamp = Stopwatch.GetTimestamp();
        var normalizedKey = NormalizeKey(key);

        try
        {
            var json = JsonSerializer.Serialize(item, _jsonOptions);
            await _database.StringSetAsync(normalizedKey, json, expiration);

            var elapsedMs = CommonHelpers.GetElapsedMilliseconds(startTimestamp);
            _logger.CacheSet(_cacheTypeName, normalizedKey, expiration.TotalSeconds, elapsedMs);
        }
        catch (Exception ex)
        {
            var elapsedMs = CommonHelpers.GetElapsedMilliseconds(startTimestamp);
            _logger.CacheOperationError(nameof(SetAsync), _cacheTypeName, normalizedKey, elapsedMs, ex);
        }
    }

    /// <inheritdoc/>
    public async Task SetManyAsync(Dictionary<string, T> items, TimeSpan expiration)
    {
        ArgumentNullException.ThrowIfNull(items);

        if (items.Count == 0)
        {
            return;
        }

        var startTimestamp = Stopwatch.GetTimestamp();

        try
        {
            // Use Redis batch for pipelining multiple SET commands
            var batch = _database.CreateBatch();
            var tasks = new List<Task>();

            foreach (var kvp in items)
            {
                var normalizedKey = NormalizeKey(kvp.Key);
                var json = JsonSerializer.Serialize(kvp.Value, _jsonOptions);
                tasks.Add(batch.StringSetAsync(normalizedKey, json, expiration));
            }

            // Execute all commands in the batch
            batch.Execute();
            await Task.WhenAll(tasks);

            var elapsedMs = CommonHelpers.GetElapsedMilliseconds(startTimestamp);
            _logger.LogInformation("Batch cache SET completed for {Count} {CacheType} items with {ExpirationSeconds}s expiration in {ElapsedMs}ms",
              items.Count, _cacheTypeName, expiration.TotalSeconds, elapsedMs);
        }
        catch (Exception ex)
        {
            var elapsedMs = CommonHelpers.GetElapsedMilliseconds(startTimestamp);
            _logger.LogError(ex, "Batch cache SET failed for {Count} {CacheType} items in {ElapsedMs}ms",
              items.Count, _cacheTypeName, elapsedMs);
        }
    }

    /// <inheritdoc/>
    public async Task RemoveAsync(string key)
    {
        ArgumentException.ThrowIfNullOrEmpty(key);

        var startTimestamp = Stopwatch.GetTimestamp();
        var normalizedKey = NormalizeKey(key);

        try
        {
            var result = await _database.KeyDeleteAsync(normalizedKey);

            var elapsedMs = CommonHelpers.GetElapsedMilliseconds(startTimestamp);
            _logger.CacheRemove(_cacheTypeName, normalizedKey, result, elapsedMs);
        }
        catch (Exception ex)
        {
            var elapsedMs = CommonHelpers.GetElapsedMilliseconds(startTimestamp);
            _logger.CacheOperationError(nameof(RemoveAsync), _cacheTypeName, normalizedKey, elapsedMs, ex);
        }
    }

    private T? PopulateResultFromCache(string normalizedKey, RedisValue value)
    {
        if (value.IsNullOrEmpty)
        {
            _logger.CacheMiss(nameof(GetManyAsync), _cacheTypeName, normalizedKey, 0);
            return null;
        }
        else
        {
            try
            {
                var item = JsonSerializer.Deserialize<T>(value!, _jsonOptions);
                if (item != null)
                {
                    _logger.CacheHit(nameof(GetManyAsync), _cacheTypeName, normalizedKey, 0);
                }
                else
                {
                    _logger.CacheMiss(nameof(GetManyAsync), _cacheTypeName, normalizedKey, 0);
                }

                return item;
            }
            catch (JsonException ex)
            {
                _logger.DeserializationError(_cacheTypeName, normalizedKey, 0, ex);
                return null;
            }
        }
    }

    /// <summary>
    /// Attempts to retrieve and deserialize an item from the cache.
    /// </summary>
    /// <param name="normalizedKey">The normalized cache key.</param>
    /// <param name="operationName">The name of the calling operation for logging purposes.</param>
    /// <param name="startTimestamp">The timestamp when the operation started.</param>
    /// <returns>A tuple containing the deserialized item (or null) and a flag indicating if the item was found in cache.</returns>
    private async Task<(T? item, bool foundInCache)> TryGetFromCacheAsync(string normalizedKey, string operationName, long startTimestamp)
    {
        var value = await _database.StringGetAsync(normalizedKey);

        if (value.IsNullOrEmpty)
        {
            var elapsedMs = CommonHelpers.GetElapsedMilliseconds(startTimestamp);
            _logger.CacheMiss(operationName, _cacheTypeName, normalizedKey, elapsedMs);
            return (null, false);
        }

        try
        {
            var result = JsonSerializer.Deserialize<T>(value!, _jsonOptions);
            var elapsedMs = CommonHelpers.GetElapsedMilliseconds(startTimestamp);

            if (result != null)
            {
                _logger.CacheHit(operationName, _cacheTypeName, normalizedKey, elapsedMs);
                return (result, true);
            }
            else
            {
                // Deserialized to null - should never happen, but treat as cache miss
                elapsedMs = CommonHelpers.GetElapsedMilliseconds(startTimestamp);
                _logger.CacheMiss(operationName, _cacheTypeName, normalizedKey, elapsedMs);
                return (null, false);
            }
        }
        catch (JsonException ex)
        {
            var elapsedMs = CommonHelpers.GetElapsedMilliseconds(startTimestamp);
            _logger.DeserializationError(_cacheTypeName, normalizedKey, elapsedMs, ex);
            // If deserialization fails, treat it as a cache miss
            return (null, false);
        }
    }

    private string NormalizeKey(string key)
    {
        return (_keyPrefix + key.Replace(':', '_')).ToLowerInvariant();
    }
}
