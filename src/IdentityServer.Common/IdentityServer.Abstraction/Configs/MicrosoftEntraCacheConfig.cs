namespace IdentityServer.Abstraction.Configs;

public class MicrosoftEntraCacheConfig : IMicrosoftEntraCacheConfig
{
    public bool Enabled { get; } = true;
    public TimeSpan ApplicationExpiration { get; } = TimeSpan.FromMinutes(15);
    public TimeSpan GroupExpiration { get; } = TimeSpan.FromMinutes(15);
    public TimeSpan UserExpiration { get; } = TimeSpan.FromMinutes(5);
}
