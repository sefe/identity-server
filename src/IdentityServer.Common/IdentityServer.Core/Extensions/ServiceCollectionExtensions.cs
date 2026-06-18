using Microsoft.Extensions.DependencyInjection;

namespace IdentityServer.Core.Extensions;

public static class ServiceCollectionExtensions
{
    private const string _decoratedServiceKeySuffix = "+Decorated";

    /// <summary>
    /// Decorates last registered service of type <typeparamref name="TService"/>
    /// using the specified type <typeparamref name="TDecorator"/>.
    /// </summary>
    /// <param name="services">The services to add to.</param>
    /// <exception cref="ArgumentNullException">If the <paramref name="services"/> argument is <c>null</c>.</exception>
    public static IServiceCollection Decorate<TService, TDecorator>(this IServiceCollection services)
        where TDecorator : TService
    {
        ArgumentNullException.ThrowIfNull(services);
        var serviceType = typeof(TService);
        var decoratorType = typeof(TDecorator);

        for (var i = services.Count - 1; i >= 0; i--)
        {
            var serviceDescriptor = services[i];
            // find non-decorated last registered service of the corresponding type
            if (serviceDescriptor.IsDecorated() || serviceDescriptor.ServiceType != serviceType)
            {
                continue;
            }

            var serviceKey = GetDecoratorKey(serviceDescriptor);

            // Replace original with a keyed service to resolve by the decorator factory in the next step
            services[i] = serviceDescriptor.WithServiceKey(serviceKey);
            // Add decorated service
            services.Add(serviceDescriptor.WithImplementationFactory(CreateDecorator(serviceType, decoratorType, serviceKey)));

            break;
        }
        return services;
    }

    /// <summary>
    /// Returns <c>true</c> if the specified service is already decorated by the extension means.
    /// </summary>
    /// <param name="descriptor">The service descriptor.</param>
    public static bool IsDecorated(this ServiceDescriptor descriptor) =>
        descriptor.ServiceKey is string stringKey
            && stringKey.EndsWith(_decoratedServiceKeySuffix, StringComparison.Ordinal);

    private static string GetDecoratorKey(ServiceDescriptor descriptor)
    {
        var uniqueId = Guid.NewGuid().ToString("n");

        if (descriptor.ServiceKey is null)
        {
            return $"{descriptor.ServiceType.Name}+{uniqueId}{_decoratedServiceKeySuffix}";
        }

        if (descriptor.ServiceKey is string stringKey)
        {
            return $"{stringKey}+{uniqueId}{_decoratedServiceKeySuffix}";
        }

        throw new NotImplementedException("Non-string ServiceKey are not supported.");
    }

    private static Func<IServiceProvider, object?, object> CreateDecorator(Type serviceType, Type decoratorType, string serviceKey)
    {
        return (serviceProvider, _) =>
        {
            var instanceToDecorate = serviceProvider.GetRequiredKeyedService(serviceType, serviceKey);
            return ActivatorUtilities.CreateInstance(serviceProvider, decoratorType, instanceToDecorate);
        };
    }
}

internal static class ServiceDescriptorExtensions
{
    public static ServiceDescriptor WithImplementationFactory(this ServiceDescriptor descriptor, Func<IServiceProvider, object?, object> implementationFactory) =>
        new(descriptor.ServiceType, descriptor.ServiceKey, implementationFactory, descriptor.Lifetime);

    public static ServiceDescriptor WithServiceKey(this ServiceDescriptor descriptor, string serviceKey) =>
        descriptor.IsKeyedService ? ReplaceServiceKey(descriptor, serviceKey) : AddServiceKey(descriptor, serviceKey);

    private static ServiceDescriptor ReplaceServiceKey(ServiceDescriptor descriptor, string serviceKey) => descriptor switch
    {
        { KeyedImplementationType: not null } => new ServiceDescriptor(descriptor.ServiceType, serviceKey, descriptor.KeyedImplementationType, descriptor.Lifetime),
        { KeyedImplementationFactory: not null } => new ServiceDescriptor(descriptor.ServiceType, serviceKey, descriptor.KeyedImplementationFactory, descriptor.Lifetime),
        { KeyedImplementationInstance: not null } => new ServiceDescriptor(descriptor.ServiceType, serviceKey, descriptor.KeyedImplementationInstance),
        _ => throw new ArgumentException($"No implementation factory or instance or type found for {descriptor.ServiceType}.", nameof(descriptor))
    };

    private static ServiceDescriptor AddServiceKey(ServiceDescriptor descriptor, string serviceKey) => descriptor switch
    {
        { ImplementationType: not null } => new ServiceDescriptor(descriptor.ServiceType, serviceKey, descriptor.ImplementationType, descriptor.Lifetime),
        { ImplementationFactory: not null } => new ServiceDescriptor(descriptor.ServiceType, serviceKey, GetKeyedFactory(descriptor.ImplementationFactory), descriptor.Lifetime),
        { ImplementationInstance: not null } => new ServiceDescriptor(descriptor.ServiceType, serviceKey, descriptor.ImplementationInstance),
        _ => throw new ArgumentException($"No implementation factory or instance or type found for {descriptor.ServiceType}.", nameof(descriptor))
    };

    private static Func<IServiceProvider, object?, object> GetKeyedFactory(Func<IServiceProvider, object> factory) => (sp, key) => factory(sp);
}
