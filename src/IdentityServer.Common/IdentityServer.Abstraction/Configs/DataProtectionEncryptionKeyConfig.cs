namespace IdentityServer.Abstraction.Configs;

public class DataProtectionEncryptionKeyConfig
{
    public string KeyVaultUrl { get; set; } = string.Empty;
    public string KeyName { get; set; } = string.Empty;
}