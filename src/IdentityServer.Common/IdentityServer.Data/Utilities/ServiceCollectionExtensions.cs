// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Infrastructure;
using Microsoft.Extensions.DependencyInjection;
using System.Diagnostics.CodeAnalysis;
using IdentityServer.Data.DbContexts;

namespace IdentityServer.Data.Utilities;

[ExcludeFromCodeCoverage]
public static class ServiceCollectionExtensions
{
    public static IIdentityServerBuilder ConfigureIdentityServerStores(this IIdentityServerBuilder builder, string connectionString,
        Action<SqlServerDbContextOptionsBuilder>? sqlServerOptionsAction = null)
    {
        return builder
            .ConfigureIdentityServerConfigurationStore(connectionString, sqlServerOptionsAction)
            .ConfigureIdentityServerOperationalStore(connectionString, sqlServerOptionsAction);
    }

    public static IIdentityServerBuilder ConfigureIdentityServerConfigurationStore(this IIdentityServerBuilder builder, string connectionString,
        Action<SqlServerDbContextOptionsBuilder>? sqlServerOptionsAction = null)
    {
        return builder
            .AddConfigurationStore<IdentityServerConfigurationDbContext>(options => // ConfigurationDbContext
            {
                options.ConfigureDbContext = optionsBuilder => optionsBuilder.UseSqlServer(connectionString, sqlServerOptionsAction);
            });
    }

    public static IIdentityServerBuilder ConfigureIdentityServerOperationalStore(this IIdentityServerBuilder builder, string connectionString,
        Action<SqlServerDbContextOptionsBuilder>? sqlServerOptionsAction = null)
    {
        return builder
            .AddOperationalStore<IdentityServerOperationalDbContext>(options => // PersistedGrantDbContext and Data Protection keys
            {
                options.ConfigureDbContext = optionsBuilder => optionsBuilder.UseSqlServer(connectionString, sqlServerOptionsAction);
                options.EnableTokenCleanup = true;
            });
    }
}
