namespace IdentityServer.Abstraction.Configs;

public class HttpRetryPolicyConfig : IHttpRetryPolicyConfig
{
    public int RetryCount { get; set; } = 1;

    public double GrowthFactorInSeconds { get; set; } = 2.0;

    public double DefaultTimeoutInSeconds { get; set; } = 100; // default HttpClient timeout
}
