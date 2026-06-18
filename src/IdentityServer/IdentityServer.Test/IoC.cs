using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Diagnostics;
using Microsoft.Extensions.DependencyInjection;
using IdentityServer.Abstraction;
using IdentityServer.Data;
using IdentityServer.Tests.Common;

namespace IdentityServer.Test;

public static class IoC
{
    public static IServiceProvider GetProvider(Action<ServiceCollection> configureServiceCollection)
    {
        var services = BuildServiceCollection();
        configureServiceCollection(services);
        var serviceProvider = services.BuildServiceProvider();
        return serviceProvider;
    }
    public static T Resolve<T>(Action<ServiceCollection> configureServiceCollection)
    {
        var serviceProvider = GetProvider(configureServiceCollection);
        return serviceProvider.GetRequiredService<T>();
    }

    public static ServiceCollection BuildServiceCollection()
    {
        var services = new ServiceCollection();
        services.AddLogging();
        services.AddDataLayerForApi();
        services.AddSingleton<ICurrentUserService, MockCurrentUserService>();
        services.AddConfigurationDbContext(optionsBuilder =>
        {
            optionsBuilder.ConfigureWarnings(w => w.Ignore(InMemoryEventId.TransactionIgnoredWarning));
            optionsBuilder.UseInMemoryDatabase(databaseName: Guid.NewGuid().ToString());
        });
        return services;
    }

    /// <summary>
    /// Replaces the existing registration of a service with a new implementation.
    /// </summary>
    /// <typeparam name="TInterface">The interface type to replace.</typeparam>
    /// <typeparam name="TImplementation">The new implementation type.</typeparam>
    /// <param name="services">The service collection.</param>
    /// <param name="lifetime">The service lifetime for the new implementation.</param>
    public static void Replace<TInterface, TImplementation>(
        this IServiceCollection services,
        ServiceLifetime lifetime)
        where TInterface : class
        where TImplementation : class, TInterface
    {
        // Remove existing registrations for the interface
        var existingRegistration = services.FirstOrDefault(
            d => d.ServiceType == typeof(TInterface));

        if (existingRegistration != null)
        {
            services.Remove(existingRegistration);
        }

        // Add the new implementation with the specified lifetime
        var descriptor = new ServiceDescriptor(typeof(TInterface), typeof(TImplementation), lifetime);
        services.Add(descriptor);
    }

    /// <summary>
    /// Replaces the existing registration of a service with a specific instance.
    /// </summary>
    /// <typeparam name="TInterface">The interface type to replace.</typeparam>
    /// <param name="services">The service collection.</param>
    /// <param name="instance">The specific instance to register.</param>
    public static void ReplaceWithInstance<TInterface>(
        this IServiceCollection services,
        TInterface instance)
        where TInterface : class
    {
        ArgumentNullException.ThrowIfNull(instance);

        // Remove existing registrations for the interface
        var existingRegistration = services.FirstOrDefault(
            d => d.ServiceType == typeof(TInterface));

        if (existingRegistration != null)
        {
            services.Remove(existingRegistration);
        }

        // Add the specific instance
        services.AddSingleton(typeof(TInterface), instance);
    }
}
