using IdentityServer.Abstraction.Contracts;

namespace IdentityServer.Core.Caching;

/// <summary>
/// A no-operation cache implementation that does not perform any caching.
/// </summary>
/// <typeparam name="T">The type of objects to cache.</typeparam>
public class NoOpCache<T> : ICache<T> where T : class
{
    public Task<T?> GetAsync(string key)
    {
        return Task.FromResult<T?>(default);
    }

    public Task<Dictionary<string, T?>> GetManyAsync(IEnumerable<string> keys)
    {
        var result = keys.Distinct().ToDictionary(key => key, _ => default(T));
        return Task.FromResult(result);
    }

    public Task<T> GetOrAddAsync(string key, TimeSpan duration, Func<Task<T>> get)
    {
        return get();
    }

    public Task SetAsync(string key, T item, TimeSpan expiration)
    {
        return Task.CompletedTask;
    }

    public Task SetManyAsync(Dictionary<string, T> items, TimeSpan expiration)
    {
        return Task.CompletedTask;
    }

    public Task RemoveAsync(string key)
    {
        return Task.CompletedTask;
    }
}
