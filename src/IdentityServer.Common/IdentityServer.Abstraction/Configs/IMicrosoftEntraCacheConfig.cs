namespace IdentityServer.Abstraction.Configs;

public interface IMicrosoftEntraCacheConfig
{
    bool Enabled { get; }
    TimeSpan ApplicationExpiration { get; }
    TimeSpan GroupExpiration { get; }
    TimeSpan UserExpiration { get; }
}
