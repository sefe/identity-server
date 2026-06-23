// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

using IdentityServer.Abstraction.Configs;
using IdentityServer.Abstraction.Contracts;
using IdentityServer.Abstraction.Contracts.MicrosoftGraph;
using IdentityServer.Abstraction.Entities.EntraEntities;

namespace IdentityServer.MicrosoftGraph.Caching;

/// <summary>
/// Caching decorator for <see cref="IEntraApplicationService"/>.
/// </summary>
internal class EntraApplicationCachedService : IEntraApplicationService
{
    private readonly IEntraApplicationService _inner;
    private readonly ICache<Application> _cache;
    private readonly IMicrosoftEntraCacheConfig _cacheConfig;

    public EntraApplicationCachedService(
        IEntraApplicationService inner,
        ICache<Application> cache,
        IMicrosoftEntraCacheConfig cacheConfig)
    {
        _inner = inner;
        _cache = cache;
        _cacheConfig = cacheConfig;
    }

    public Task<Application?> GetByIdAsync(string appId)
    {
        return _cache.GetOrAddAsync(
            appId,
            _cacheConfig.ApplicationExpiration,
            () => _inner.GetByIdAsync(appId)!)!;
    }
}
