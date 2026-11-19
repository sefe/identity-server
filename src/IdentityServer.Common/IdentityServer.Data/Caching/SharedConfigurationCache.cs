// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

using Microsoft.Extensions.Caching.Hybrid;

namespace IdentityServer.Data.Caching;

/// <summary>
/// Prevents a server's L1 cache from hiding invalidations made by the admin portal
/// or another server. Duende supplies per-call options, so enforce this per call.
/// </summary>
internal sealed class SharedConfigurationCache(HybridCache inner) : HybridCache
{
    private static HybridCacheEntryOptions SharedOptions(HybridCacheEntryOptions? options) => new()
    {
        Expiration = options?.Expiration,
        LocalCacheExpiration = options?.LocalCacheExpiration,
        Flags = (options?.Flags ?? HybridCacheEntryFlags.None)
            | HybridCacheEntryFlags.DisableLocalCacheRead
            | HybridCacheEntryFlags.DisableLocalCacheWrite
    };

    public override ValueTask<T> GetOrCreateAsync<TState, T>(
        string key, TState state, Func<TState, CancellationToken, ValueTask<T>> factory,
        HybridCacheEntryOptions? options = null, IEnumerable<string>? tags = null,
        CancellationToken cancellationToken = default) =>
        inner.GetOrCreateAsync(key, state, factory, SharedOptions(options), tags, cancellationToken);

    public override ValueTask SetAsync<T>(string key, T value, HybridCacheEntryOptions? options = null,
        IEnumerable<string>? tags = null, CancellationToken cancellationToken = default) =>
        inner.SetAsync(key, value, SharedOptions(options), tags, cancellationToken);

    public override ValueTask RemoveAsync(string key, CancellationToken cancellationToken = default) =>
        inner.RemoveAsync(key, cancellationToken);

    public override ValueTask RemoveByTagAsync(string tag, CancellationToken cancellationToken = default) =>
        inner.RemoveByTagAsync(tag, cancellationToken);
}
