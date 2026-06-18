using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using IdentityServer.Abstraction.Configs;

namespace IdentityServer.Core.Extensions;

public static class HttpRetryPolicyExtensions
{
    public const string SectionName = "HttpRetryPolicy";

    public static IHttpRetryPolicyConfig GetHttpRetryPolicy(this IConfiguration configuration)
    {
        return configuration.GetSection(SectionName).Get<HttpRetryPolicyConfig>()
                    ?? new HttpRetryPolicyConfig();
    }

    public static IServiceCollection ConfigureRetryPolicy(this IServiceCollection serviceCollection, IConfiguration configuration)
    {
        var retryPolicy = configuration.GetHttpRetryPolicy();
        serviceCollection.AddSingleton(retryPolicy);

        return serviceCollection;
    }
}
