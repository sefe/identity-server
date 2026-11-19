// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

using Duende.IdentityServer;
using Duende.IdentityServer.Configuration;
using Duende.IdentityServer.EntityFramework.DbContexts;
using Duende.IdentityServer.EntityFramework.Options;
using Duende.IdentityServer.EntityFramework.Services;
using Duende.IdentityServer.EntityFramework.Stores;
using Duende.IdentityServer.Models;
using Duende.IdentityServer.Stores;
using IdentityServer.Abstraction.Contracts;
using IdentityServer.Abstraction.Configs;
using IdentityServer.Core.Caching;
using IdentityServer.Data.Caching;
using Microsoft.Extensions.Caching.Distributed;
using Microsoft.Extensions.Caching.Hybrid;
using Microsoft.Extensions.Caching.Memory;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging.Abstractions;
using Microsoft.Extensions.Options;
using Microsoft.EntityFrameworkCore;
using NSubstitute;
using StackExchange.Redis;
using DataEntities = Duende.IdentityServer.EntityFramework.Entities;
using CorsCacheEntry = Duende.IdentityServer.Stores.CachingCorsPolicyService<Duende.IdentityServer.EntityFramework.Services.CorsPolicyService>.CorsCacheEntry;

namespace IdentityServer.Data.Test.Caching;

[TestFixture]
public class ConfigurationCacheTests
{
    private static ServiceProvider CreateProvider(IDistributedCache backend)
    {
        var services = new ServiceCollection();
        services.AddLogging();
        services.AddSingleton(typeof(ICache<>), typeof(NoOpCache<>));
        services.AddSharedConfigurationCache();
        services.AddKeyedSingleton(ConfigurationCacheServiceCollectionExtensions.SharedCacheKey, backend);
        services.AddIdentityServer()
            .AddClientStoreCache<ClientStore>()
            .AddResourceStoreCache<ResourceStore>()
            .AddCorsPolicyCache<CorsPolicyService>()
            .AddIdentityProviderStoreCache<IdentityProviderStore>();
        return services.BuildServiceProvider();
    }

    private static HybridCache Cache(ServiceProvider provider) =>
        provider.GetRequiredKeyedService<HybridCache>(ServiceProviderKeys.ConfigurationStoreCache);

    [TestCase("QA")]
    [TestCase("Production")]
    public async Task RedisBackend_UsesSharedConnection_AndEnvironmentNamespace(string environment)
    {
        var services = new ServiceCollection();
        var system = Substitute.For<ISystemConfig>();
        system.Environment.Returns(environment);
        using var connection = Substitute.For<IConnectionMultiplexer>();
        var database = Substitute.For<IDatabase>();
        connection.GetDatabase(Arg.Any<int>(), Arg.Any<object>()).Returns(database);
        services.AddSingleton(system);
        services.AddSingleton(connection);
        services.AddSharedConfigurationCache();
        using var provider = services.BuildServiceProvider();
        var backend = provider.GetRequiredKeyedService<IDistributedCache>(
            ConfigurationCacheServiceCollectionExtensions.SharedCacheKey);

        await backend.RemoveAsync("IS:Duende.IdentityServer.Models.Client-Client-A");

        await database.Received(1).KeyDeleteAsync(
            $"{environment}:configuration:v8:IS:Duende.IdentityServer.Models.Client-Client-A", Arg.Any<CommandFlags>());
    }

    [Test]
    public async Task ClientInvalidation_RefreshesEveryServer_WithoutWaitingForLocalExpiration()
    {
        var backend = new SharedTestBackend();
        using var serverOne = CreateProvider(backend);
        using var serverTwo = CreateProvider(backend);
        using var admin = CreateProvider(backend);
        var inner = Substitute.For<IClientStore>();
        var enabled = true;
        inner.FindClientByIdAsync("Client-A", Arg.Any<CancellationToken>())
            .Returns(_ => new Client { ClientId = "Client-A", Enabled = enabled });
        var one = new CachingClientStore<IClientStore>(new IdentityServerOptions(), inner, Cache(serverOne));
        var two = new CachingClientStore<IClientStore>(new IdentityServerOptions(), inner, Cache(serverTwo));

        Assert.That((await one.FindClientByIdAsync("Client-A", default)).Enabled, Is.True);
        Assert.That((await two.FindClientByIdAsync("Client-A", default)).Enabled, Is.True);
        await inner.Received(1).FindClientByIdAsync("Client-A", Arg.Any<CancellationToken>());
        Assert.That(backend.WrittenKeys, Does.Contain("IS:Duende.IdentityServer.Models.Client-Client-A"));
        Assert.That(serverOne.GetRequiredService<ICache<Client>>(), Is.TypeOf<NoOpCache<Client>>());

        enabled = false;
        await admin.GetRequiredService<IConfigurationCacheInvalidator<DataEntities.Client>>().RemoveAsync("Client-A");

        Assert.That((await one.FindClientByIdAsync("Client-A", default)).Enabled, Is.False);
        Assert.That((await two.FindClientByIdAsync("Client-A", default)).Enabled, Is.False);
        await inner.Received(2).FindClientByIdAsync("Client-A", Arg.Any<CancellationToken>());
    }

    [Test]
    public async Task ClientKeys_PreserveCase()
    {
        var backend = new SharedTestBackend();
        using var server = CreateProvider(backend);
        using var admin = CreateProvider(backend);
        var inner = Substitute.For<IClientStore>();
        inner.FindClientByIdAsync(Arg.Any<string>(), Arg.Any<CancellationToken>())
            .Returns(call => new Client { ClientId = call.Arg<string>() });
        var store = new CachingClientStore<IClientStore>(new IdentityServerOptions(), inner, Cache(server));
        await store.FindClientByIdAsync("Client", default);
        await store.FindClientByIdAsync("client", default);

        await admin.GetRequiredService<IConfigurationCacheInvalidator<DataEntities.Client>>().RemoveAsync("Client");
        await store.FindClientByIdAsync("Client", default);
        await store.FindClientByIdAsync("client", default);

        await inner.Received(2).FindClientByIdAsync("Client", Arg.Any<CancellationToken>());
        await inner.Received(1).FindClientByIdAsync("client", Arg.Any<CancellationToken>());
    }

    [TestCase(false)]
    [TestCase(true)]
    public async Task ResourceOrScopeInvalidation_RefreshesEntireSnapshot(bool scopeChange)
    {
        var backend = new SharedTestBackend();
        using var server = CreateProvider(backend);
        using var admin = CreateProvider(backend);
        var inner = Substitute.For<IResourceStore>();
        var resources = new Resources();
        inner.GetAllResourcesAsync(Arg.Any<CancellationToken>()).Returns(_ => resources);
        var store = new CachingResourceStore<IResourceStore>(new IdentityServerOptions(), inner, Cache(server));
        Assert.That((await store.GetAllResourcesAsync(default)).ApiResources, Is.Empty);

        resources = new Resources([], [new ApiResource("Api") { Scopes = ["Scope"] }], [new ApiScope("Scope")]);
        if (scopeChange)
        {
            await admin.GetRequiredService<IConfigurationCacheInvalidator<DataEntities.ApiScope>>().RemoveAsync("Scope");
        }
        else
        {
            await admin.GetRequiredService<IConfigurationCacheInvalidator<DataEntities.ApiResource>>().RemoveAsync("Api");
        }

        Assert.That(await store.FindApiResourcesByNameAsync(["Api"], default), Has.Count.EqualTo(1));
        Assert.That(await store.FindApiResourcesByScopeNameAsync(["Scope"], default), Has.Count.EqualTo(1));
        Assert.That(await store.FindApiScopesByNameAsync(["Scope"], default), Has.Count.EqualTo(1));
        Assert.That(backend.WrittenKeys, Does.Contain("IS:Duende.IdentityServer.Models.Resources-__all__"));
        await inner.Received(2).GetAllResourcesAsync(Arg.Any<CancellationToken>());

        resources = new Resources();
        await admin.GetRequiredService<IConfigurationCacheInvalidator<DataEntities.ApiResource>>().RemoveAsync("Api");
        Assert.That((await store.GetAllResourcesAsync(default)).ApiResources, Is.Empty);
        Assert.That(await store.FindApiScopesByNameAsync(["Scope"], default), Is.Empty);
    }

    [Test]
    public async Task CorsInvalidation_RefreshesPositiveAndNegativeDecisions()
    {
        var backend = new SharedTestBackend();
        using var server = CreateProvider(backend);
        using var admin = CreateProvider(backend);
        using var db = new ConfigurationDbContext(new DbContextOptionsBuilder<ConfigurationDbContext>()
            .UseInMemoryDatabase(Guid.NewGuid().ToString()).Options) { StoreOptions = new ConfigurationStoreOptions() };
        var inner = new CorsPolicyService(db, NullLogger<CorsPolicyService>.Instance);
        const string origin = "https://app.example";
        var store = new CachingCorsPolicyService<CorsPolicyService>(new IdentityServerOptions(), inner, Cache(server));
        var invalidator = admin.GetRequiredService<IConfigurationCacheInvalidator<CorsCacheEntry>>();
        Assert.That(await store.IsOriginAllowedAsync(origin, default), Is.False);

        var entry = new DataEntities.ClientCorsOrigin { Origin = origin, ClientId = 1 };
        db.ClientCorsOrigins.Add(entry);
        await db.SaveChangesAsync();
        await invalidator.RemoveAsync(origin);
        Assert.That(await store.IsOriginAllowedAsync(origin, default), Is.True);

        db.ClientCorsOrigins.Remove(entry);
        await db.SaveChangesAsync();
        await invalidator.RemoveAsync(origin);
        Assert.That(await store.IsOriginAllowedAsync(origin, default), Is.False);
        Assert.That(backend.WrittenKeys, Does.Contain($"IS:{typeof(CorsCacheEntry).FullName}-{origin}"));
    }

    [Test]
    public async Task ExplicitPerCallFlags_CannotEnableLocalCaching()
    {
        var backend = new SharedTestBackend();
        using var server = CreateProvider(backend);
        using var admin = CreateProvider(backend);
        var options = new HybridCacheEntryOptions { Flags = HybridCacheEntryFlags.None };
        await Cache(server).SetAsync("test-key", "old", options);
        await Cache(admin).RemoveAsync("test-key");

        var result = await Cache(server).GetOrCreateAsync("test-key", _ => ValueTask.FromResult("new"), options);
        Assert.That(result, Is.EqualTo("new"));
    }

    [Test]
    public async Task InvalidationFailure_IsNotSilentlyIgnored()
    {
        var cache = Substitute.For<HybridCache>();
        cache.RemoveAsync(Arg.Any<string>(), Arg.Any<CancellationToken>())
            .Returns(_ => ValueTask.FromException(new InvalidOperationException("Cache unavailable")));
        var invalidator = new ConfigurationCacheInvalidator<DataEntities.Client>(cache);

        await Assert.ThrowsAsync<InvalidOperationException>(() => invalidator.RemoveAsync("client"));
    }

    // A distinct type prevents HybridCache treating this shared backend as its own L1.
    private sealed class SharedTestBackend : IDistributedCache
    {
        private readonly MemoryDistributedCache _inner = new(Options.Create(new MemoryDistributedCacheOptions()));
        public List<string> WrittenKeys { get; } = [];

        public byte[] Get(string key) => _inner.Get(key);
        public Task<byte[]> GetAsync(string key, CancellationToken token = default) => _inner.GetAsync(key, token);
        public void Refresh(string key) => _inner.Refresh(key);
        public Task RefreshAsync(string key, CancellationToken token = default) => _inner.RefreshAsync(key, token);
        public void Remove(string key) => _inner.Remove(key);
        public Task RemoveAsync(string key, CancellationToken token = default) => _inner.RemoveAsync(key, token);
        public void Set(string key, byte[] value, DistributedCacheEntryOptions options)
        {
            WrittenKeys.Add(key);
            _inner.Set(key, value, options);
        }

        public Task SetAsync(string key, byte[] value, DistributedCacheEntryOptions options,
            CancellationToken token = default)
        {
            WrittenKeys.Add(key);
            return _inner.SetAsync(key, value, options, token);
        }
    }
}
