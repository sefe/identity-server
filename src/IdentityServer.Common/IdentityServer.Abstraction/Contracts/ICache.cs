namespace IdentityServer.Abstraction.Contracts;

public interface ICache<T> where T : class
{
    Task<T?> GetAsync(string key);

    /// <summary>
    /// Gets multiple items from cache.
    /// </summary>
    /// <param name="keys">The cache keys to retrieve.</param>
    /// <returns>A dictionary mapping keys to their cached values. Missing or null values are returned as null.</returns>
    Task<Dictionary<string, T?>> GetManyAsync(IEnumerable<string> keys);

    Task<T> GetOrAddAsync(string key, TimeSpan duration, Func<Task<T>> get);

    Task SetAsync(string key, T item, TimeSpan expiration);

    /// <summary>
    /// Sets multiple items in cache.
    /// </summary>
    /// <param name="items">Dictionary of key-value pairs to cache.</param>
    /// <param name="expiration">The expiration time for all items.</param>
    Task SetManyAsync(Dictionary<string, T> items, TimeSpan expiration);

    Task RemoveAsync(string key);
}
