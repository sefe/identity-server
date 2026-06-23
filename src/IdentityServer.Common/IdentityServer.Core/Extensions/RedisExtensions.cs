// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

using Microsoft.Extensions.DependencyInjection;
using StackExchange.Redis;
using System.Diagnostics.CodeAnalysis;

namespace IdentityServer.Core.Extensions;

[ExcludeFromCodeCoverage]
public static class RedisExtensions
{
    public static IServiceCollection AddRedisConnection(this IServiceCollection services, ConfigurationOptions redisOptions)
    {
        services.AddSingleton<IConnectionMultiplexer>(sp =>
        {
            return ConnectionMultiplexer.Connect(redisOptions);
        });

        return services;
    }
}
