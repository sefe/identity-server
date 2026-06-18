using StackExchange.Redis;
using IdentityServer.Abstraction.Configs;
using IdentityServer.Abstraction.Exceptions;

namespace IdentityServer.Core.Caching;

public static class RedisConnectionStringBuilder
{
    public static ConfigurationOptions BuildFrom(CacheProvider settings)
    {
        if (string.IsNullOrEmpty(settings.ConnectionString))
        {
            throw new IdentityServerException("Valkey connection string is not configured (IdentityServer:CachingOptions:Provider:ConnectionString)");
        }
        if (string.IsNullOrEmpty(settings.Username))
        {
            throw new IdentityServerException("Valkey username is not configured (IdentityServer:CachingOptions:Provider:Username)");
        }
        if (string.IsNullOrEmpty(settings.Password))
        {
            throw new IdentityServerException("Valkey password is not configured (IdentityServer:CachingOptions:Provider:Password)");
        }

        var options = ConfigurationOptions.Parse(settings.ConnectionString);
        options.User = settings.Username;
        options.Password = settings.Password;
        options.Ssl = true;
        return options;
    }
}
