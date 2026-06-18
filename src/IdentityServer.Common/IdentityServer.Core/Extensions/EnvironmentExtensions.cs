using Microsoft.Extensions.Configuration;

namespace IdentityServer.Core.Extensions;

public static class EnvironmentExtensions
{
    public static string AddEnvironmentConfiguration(this ConfigurationManager configuration,
        string defaultEnv = "local",
        string argName = "env")
    {
        var environment = configuration.GetEnvironment(defaultEnv, argName);
        configuration.AddJsonFile($"appsettings.{environment}.json", true);

        return environment;
    }

    /// <summary>
    /// Attempts to get the "environment" the application is running in by
    /// looking for a command line argument "environment" then fallback
    /// to the default env supplied (Debug platform config only, cmdline arg
    /// MUST be supplied in Release builds)
    /// </summary>
    /// <param name="configuration">the command line args</param>
    /// <param name="defaultEnv">the default environment to use if none found, defaults to "local"</param>
    /// <param name="argName">the name of the cmdline arg, defaults to "env"</param>
    /// <returns></returns>
    public static string GetEnvironment(this ConfigurationManager configuration, string defaultEnv = "local", string argName = "env")
    {
        var env = configuration[argName];

#if DEBUG
        // allow fallback to default in development/debug build 
        env ??= defaultEnv;
#else
        // deployed/server environments must have this set
        if (string.IsNullOrWhiteSpace(env))
        {
            throw new InvalidOperationException($"Cmdline arg '{argName}' must be supplied to set the environment");
        }
#endif
        return env;
    }
}
