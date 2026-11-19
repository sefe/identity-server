// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

using Duende.IdentityServer.EntityFramework.Services;
using Duende.IdentityServer.EntityFramework.Stores;
using IdentityServer.Data.Caching;
using System.Diagnostics.CodeAnalysis;

namespace IdentityServer.Extensions;

[ExcludeFromCodeCoverage]
public static class IdentityServerBuilderExtensions
{
    /// <summary>
    /// Adds Redis-based caching for Duende IdentityServer using Valkey/Redis.
    /// </summary>
    /// <param name="builder">The IdentityServer builder.</param>
    /// <returns>The IdentityServer builder for chaining.</returns>
    public static IIdentityServerBuilder AddSharedConfigurationStoreCache(
        this IIdentityServerBuilder builder)
    {
        builder.Services.AddSharedConfigurationCache();

        builder.AddConfigurationStoreCachingDecorators();

        return builder;
    }

    /// <summary>
    /// Configures caching for IClientStore, IResourceStore, and ICorsPolicyService with IdentityServer.
    /// Must be registered after the shared configuration cache.
    /// </summary>
    /// <param name="builder">The builder.</param>
    /// <returns></returns>
    public static IIdentityServerBuilder AddConfigurationStoreCachingDecorators(
        this IIdentityServerBuilder builder)
    {
        builder.AddClientStoreCache<ClientStore>();
        builder.AddResourceStoreCache<ResourceStore>();
        builder.AddCorsPolicyCache<CorsPolicyService>();
        builder.AddIdentityProviderStoreCache<IdentityProviderStore>();

        return builder;
    }
}
