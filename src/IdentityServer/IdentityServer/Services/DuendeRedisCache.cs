// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

using StackExchange.Redis;
using System.Diagnostics.CodeAnalysis;
using IdentityServer.Abstraction.Configs;
using IdentityServer.Core.Caching;

namespace IdentityServer.Services;

[ExcludeFromCodeCoverage]
public class DuendeRedisCache<T> : RedisCache<T> where T : class
{
    public DuendeRedisCache(IConnectionMultiplexer connectionMultiplexer, ISystemConfig systemConfig, ILogger<DuendeRedisCache<T>> logger)
        : base(connectionMultiplexer, systemConfig, logger)
    {
    }
}
