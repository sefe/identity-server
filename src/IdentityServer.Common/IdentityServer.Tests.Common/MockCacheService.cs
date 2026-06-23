// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

using IdentityServer.Abstraction.Contracts;

namespace IdentityServer.Tests.Common;

public class MockCacheService<T> : ICache<T> where T : class
{
    public Task<T> GetAsync(string key)
    {
        throw new NotImplementedException();
    }

    public Task<Dictionary<string, T>> GetManyAsync(IEnumerable<string> keys)
    {
        return Task.FromResult(new Dictionary<string, T>());
    }

    public Task<T> GetOrAddAsync(string key, TimeSpan duration, Func<Task<T>> get)
    {
        throw new NotImplementedException();
    }

    public Task RemoveAsync(string key)
    {
        return Task.CompletedTask;
    }

    public Task SetAsync(string key, T item, TimeSpan expiration)
    {
        return Task.CompletedTask;
    }

    public Task SetManyAsync(Dictionary<string, T> items, TimeSpan expiration)
    {
        return Task.CompletedTask;
    }
}
