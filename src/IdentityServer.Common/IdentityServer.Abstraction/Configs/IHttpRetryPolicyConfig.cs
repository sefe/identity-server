namespace IdentityServer.Abstraction.Configs;

public interface IHttpRetryPolicyConfig
{
    int RetryCount { get; }

    double GrowthFactorInSeconds { get; }

    double DefaultTimeoutInSeconds { get; }
}
