// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

namespace IdentityServer.Abstraction.Configs;

public class IdentityServerCachingOptions
{
    public bool Enabled { get; set; } = true;
    public CacheProvider Provider { get; set; } = new();
}

public class CacheProvider
{
    public CacheProviderKind Kind { get; set; } = CacheProviderKind.InMemory;
    public string? ConnectionString { get; set; }
    public string? Username { get; set; }
    public string? Password { get; set; }
}

public enum CacheProviderKind
{
    InMemory,
    Valkey
}
