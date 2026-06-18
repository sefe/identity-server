using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Primitives;
using IdentityServer.OnePassword.Extensions;

namespace IdentityServer.OnePassword.Tests;

[TestFixture]
public class OnePasswordExtensionsTests
{
    [Test]
    public void AddOnePasswordSecrets_SecretsEmpty_ReturnsBuilder()
    {
        // Arrange
        var config = new OnePasswordConfig
        {
            BaseUrl = "https://api.1password.com",
            AccessToken = "token",
            VaultId = "vault",
            Secrets = new Dictionary<string, string>()
        };
        var builder = new ConfigurationBuilder();
        builder.AddInMemoryCollection(
            new Dictionary<string, string?> {
                { "OnePassword:BaseUrl", config.BaseUrl },
                { "OnePassword:AccessToken", config.AccessToken },
                { "OnePassword:VaultId", config.VaultId }
            });

        // Act
        var result = builder.AddOnePasswordSecrets();

        // Assert
        Assert.That(result, Is.SameAs(builder));
    }

    [Test]
    public void RemoveAlreadyPresentConfigEntries_RemovesKeysWithNonEmptyConfig()
    {
        // Arrange
        var config = new OnePasswordConfig
        {
            BaseUrl = "https://api.1password.com",
            AccessToken = "token",
            VaultId = "vault",
            Secrets = new Dictionary<string, string> { { "My__Secret", "itemId" }, { "Other__Secret", "itemId2" } }
        };
        var configRoot = new TestConfigRoot(new Dictionary<string, string?> { { "My:Secret", "value" }, { "Other:Secret", null! } });

        // Act
        OnePasswordExtensions.RemoveAlreadyPresentConfigEntries(configRoot, config);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(config.Secrets.ContainsKey("Other__Secret"), Is.True);
            Assert.That(config.Secrets.ContainsKey("My__Secret"), Is.False);
        }
    }

    private class TestConfigRoot : IConfigurationRoot
    {
        private readonly Dictionary<string, string?> _dict;
        public TestConfigRoot(Dictionary<string, string?> dict) => _dict = dict;
        public string? this[string key] { get => _dict.TryGetValue(key, out string? value) ? value : null; set => _dict[key] = value; }
        public IEnumerable<IConfigurationProvider> Providers => throw new NotImplementedException();
        public IEnumerable<IConfigurationSection> GetChildren() => new List<IConfigurationSection>();
        public IChangeToken GetReloadToken() => new CancellationChangeToken(new CancellationToken());
        public IConfigurationSection GetSection(string key) => null!;
        public void Reload() => throw new NotImplementedException();
    }
}
