using Microsoft.Extensions.Logging;

namespace IdentityServer.Core.Caching;

internal static class RedisLog
{
    private const int _redisEventOffset = 860;
    private static readonly Action<ILogger, string, string, string, double, Exception?> _cacheHit =
        LoggerMessage.Define<string, string, string, double>(
            LogLevel.Debug,
            new EventId(_redisEventOffset + 1, "CacheHit"),
            "Cache hit: Operation={Operation}, CacheType={CacheType}, Key={CacheKey}, DurationMs={DurationMs:F2}");

    private static readonly Action<ILogger, string, string, string, double, Exception?> _cacheMiss =
        LoggerMessage.Define<string, string, string, double>(
            LogLevel.Debug,
            new EventId(_redisEventOffset + 2, "CacheMiss"),
            "Cache miss: Operation={Operation}, CacheType={CacheType}, Key={CacheKey}, DurationMs={DurationMs:F2}");

    private static readonly Action<ILogger, string, string, double, double, Exception?> _cacheSet =
        LoggerMessage.Define<string, string, double, double>(
            LogLevel.Information,
            new EventId(_redisEventOffset + 3, "CacheSet"),
            "Cache set: CacheType={CacheType}, Key={CacheKey}, ExpirationSeconds={ExpirationSeconds:F0}, DurationMs={DurationMs:F2}");

    private static readonly Action<ILogger, string, string, bool, double, Exception?> _cacheRemove =
        LoggerMessage.Define<string, string, bool, double>(
            LogLevel.Information,
            new EventId(_redisEventOffset + 4, "CacheRemove"),
            "Cache remove: CacheType={CacheType}, Key={CacheKey}, Deleted={Deleted}, DurationMs={DurationMs:F2}");

    private static readonly Action<ILogger, string, string, double, Exception?> _objectLoaded =
        LoggerMessage.Define<string, string, double>(
            LogLevel.Debug,
            new EventId(_redisEventOffset + 5, "ObjectLoaded"),
            "Object loaded from source: CacheType={CacheType}, Key={CacheKey}, LoadDurationMs={LoadDurationMs:F2}");

    private static readonly Action<ILogger, string, string, double, Exception?> _objectLoadFailed =
        LoggerMessage.Define<string, string, double>(
            LogLevel.Debug,
            new EventId(_redisEventOffset + 6, "ObjectLoadFailed"),
            "Object failed to load from source: CacheType={CacheType}, Key={CacheKey}, LoadDurationMs={LoadDurationMs:F2}");

    private static readonly Action<ILogger, string, string, double, Exception?> _deserializationError =
        LoggerMessage.Define<string, string, double>(
            LogLevel.Warning,
            new EventId(_redisEventOffset + 7, "DeserializationError"),
            "Cache deserialization error: CacheType={CacheType}, Key={CacheKey}, DurationMs={DurationMs:F2}");

    private static readonly Action<ILogger, string, string, string, double, Exception?> _cacheOperationError =
        LoggerMessage.Define<string, string, string, double>(
            LogLevel.Error,
            new EventId(_redisEventOffset + 8, "CacheOperationError"),
            "Cache operation error: Operation={Operation}, CacheType={CacheType}, Key={CacheKey}, DurationMs={DurationMs:F2}");

    public static void CacheHit(this ILogger logger, string operation, string cacheType, string key, double durationMs)
        => _cacheHit(logger, operation, cacheType, key, durationMs, null);

    public static void CacheMiss(this ILogger logger, string operation, string cacheType, string key, double durationMs)
        => _cacheMiss(logger, operation, cacheType, key, durationMs, null);

    public static void CacheSet(this ILogger logger, string cacheType, string key, double expirationSeconds, double durationMs)
        => _cacheSet(logger, cacheType, key, expirationSeconds, durationMs, null);

    public static void CacheRemove(this ILogger logger, string cacheType, string key, bool deleted, double durationMs)
        => _cacheRemove(logger, cacheType, key, deleted, durationMs, null);

    public static void ObjectLoaded(this ILogger logger, string cacheType, string key, double loadDurationMs)
        => _objectLoaded(logger, cacheType, key, loadDurationMs, null);

    public static void ObjectLoadFailed(this ILogger logger, string cacheType, string key, double loadDurationMs, Exception? exception)
        => _objectLoadFailed(logger, cacheType, key, loadDurationMs, exception);

    public static void DeserializationError(this ILogger logger, string cacheType, string key, double durationMs, Exception? exception)
        => _deserializationError(logger, cacheType, key, durationMs, exception);

    public static void CacheOperationError(this ILogger logger, string operation, string cacheType, string key, double durationMs, Exception? exception)
        => _cacheOperationError(logger, operation, cacheType, key, durationMs, exception);
}
