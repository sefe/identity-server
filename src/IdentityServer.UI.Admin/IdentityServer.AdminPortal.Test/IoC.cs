using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Diagnostics;
using Microsoft.Extensions.DependencyInjection;
using NSubstitute;
using IdentityServer.Abstraction;
using IdentityServer.Abstraction.Contracts;
using IdentityServer.Data;
using IdentityServer.Tests.Common;

namespace IdentityServer.AdminPortal.Test;

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
        services.AddDataLayerForUi();
        services.AddSingleton<ICurrentUserService, MockCurrentUserService>();
        services.AddSingleton(typeof(Abstraction.Contracts.ICache<>), typeof(MockCacheService<>));

        // Add audit service mocks globally for all integration tests
        var apiResourceAuditService = Substitute.For<IApiResourceAuditService>();
        var clientAuditService = Substitute.For<IClientAuditService>();
        var systemPermissionAuditService = Substitute.For<ISystemPermissionAuditService>();

        // Configure audit services to return empty/null results by default
        apiResourceAuditService.GetLastModifiedByIdAsync(Arg.Any<List<int>>()).Returns(new Dictionary<int, EntityLastModifiedData>());
        apiResourceAuditService.GetLastModifiedByIdAsync(Arg.Any<int>()).Returns((EntityLastModifiedData)null);
        clientAuditService.GetLastModifiedByIdAsync(Arg.Any<List<int>>()).Returns(new Dictionary<int, EntityLastModifiedData>());
        clientAuditService.GetLastModifiedByIdAsync(Arg.Any<int>()).Returns((EntityLastModifiedData)null);
        systemPermissionAuditService.GetLastModifiedByIdAsync(Arg.Any<List<int>>()).Returns(new Dictionary<int, EntityLastModifiedData>());
        systemPermissionAuditService.GetLastModifiedByIdAsync(Arg.Any<int>()).Returns((EntityLastModifiedData)null);

        services.AddSingleton(apiResourceAuditService);
        services.AddSingleton(clientAuditService);
        services.AddSingleton(systemPermissionAuditService);

        services.AddConfigurationDbContext(optionsBuilder =>
        {
            optionsBuilder.ConfigureWarnings(w => w.Ignore(InMemoryEventId.TransactionIgnoredWarning));
            optionsBuilder.UseInMemoryDatabase(databaseName: Guid.NewGuid().ToString());
        });
        return services;
    }
}
