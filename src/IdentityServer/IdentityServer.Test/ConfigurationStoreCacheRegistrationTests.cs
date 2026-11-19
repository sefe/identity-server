// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

using Duende.IdentityServer;
using Duende.IdentityServer.Stores;
using IdentityServer.Abstraction.Contracts;
using IdentityServer.Core.Caching;
using IdentityServer.Extensions;
using Microsoft.Extensions.Caching.Hybrid;
using Microsoft.Extensions.DependencyInjection;

namespace IdentityServer.Test;

[TestFixture]
public class ConfigurationStoreCacheRegistrationTests
{
    [Test]
    public void SharedConfigurationCache_RegistersDuendeKey_WithoutReplacingApplicationCache()
    {
        var services = new ServiceCollection();
        services.AddSingleton(typeof(ICache<>), typeof(RedisCache<>));
        services.AddIdentityServer().AddSharedConfigurationStoreCache();

        Assert.That(services.Single(d => d.ServiceType == typeof(ICache<>)).ImplementationType,
            Is.EqualTo(typeof(RedisCache<>)));
        Assert.That(services.Count(d => d.ServiceType == typeof(HybridCache) && d.IsKeyedService
            && Equals(d.ServiceKey, ServiceProviderKeys.ConfigurationStoreCache)), Is.EqualTo(1));
        Assert.That(services.Last(d => d.ServiceType == typeof(IClientStore)).ImplementationType
            .GetGenericTypeDefinition(), Is.EqualTo(typeof(CachingClientStore<>)));
        Assert.That(services.Last(d => d.ServiceType == typeof(IResourceStore)).ImplementationType
            .GetGenericTypeDefinition(), Is.EqualTo(typeof(CachingResourceStore<>)));
    }
}
