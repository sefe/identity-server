using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Diagnostics;
using Microsoft.Extensions.DependencyInjection;

namespace IdentityServer.Data.Test;

public static class IoC
{
    public static T Resolve<T>(Action<ServiceCollection> configureServiceCollection)
    {
        var services = BuildServiceCollection();
        configureServiceCollection(services);
        var serviceProvider = services.BuildServiceProvider();
        return serviceProvider.GetRequiredService<T>();
    }

    public static ServiceCollection BuildServiceCollection()
    {
        var services = new ServiceCollection();
        services.AddLogging();
        services.AddDataLayerForUi();
        services.AddConfigurationDbContext(optionsBuilder =>
        {
            optionsBuilder.ConfigureWarnings(w => w.Ignore(InMemoryEventId.TransactionIgnoredWarning));
            optionsBuilder.UseInMemoryDatabase(databaseName: "IdentityServer");
        });
        return services;
    }
}
