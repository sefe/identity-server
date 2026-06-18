using IdentityServer.Abstraction.DTO.Clients;
using IdentityServer.Abstraction.Entities.IdentityServerConfig;
using IdentityServer.Abstraction.Entities.IdentityServerConfig.SystemPermissions;
using IdentityServer.AdminPortal.Web;

namespace IdentityServer.AdminPortal.Test.Extensions;

[TestFixture]
public class ResourcesExtensionsTests
{
    [Test]
    public void ShallowCopy_CopiesAllProperties()
    {
        // Arrange
        var now = DateTime.UtcNow;
        var client = new ClientDtoRead
        {
            Id = 1,
            ClientId = "cid",
            ClientName = "cname",
            Description = "desc",
            Enabled = true,
            RequirePkce = true,
            RequireClientSecret = false,
            AccessTokenType = ClientAccessTokenType.Jwt,
            AllowOfflineAccess = true,
            SystemPermissionEnvironmentId = 2,
            AccessLevel = SystemPermissionRoleType.Writer,
            AllowedGrantTypes = new List<ClientPropertyGrantDtoRead> { new() { Id = 1, ClientId = 1, GrantType = "gt" } },
            RedirectUris = new List<ClientPropertyRedirectUriDtoRead> { new() { Id = 2, ClientId = 1, RedirectUri = "uri" } },
            AllowedCorsOrigins = new List<ClientPropertyCorsOriginDtoRead> { new() { Id = 3, ClientId = 1, Origin = "origin" } },
            ClientSecrets = new List<ClientPropertySecretDtoRead> { new() { Id = 4, ClientId = 1, Description = "secret", Created = now } },
            AllowedScopes = new List<ClientPropertyScopeDtoRead> { new() { Id = 5, ClientId = 1, Scope = "scope" } },
            Created = now,
            Updated = now
        };
        // Act
        var copy = client.ShallowCopy();
        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(copy, Is.Not.SameAs(client));
            Assert.That(copy.Id, Is.EqualTo(client.Id));
            Assert.That(copy.ClientId, Is.EqualTo(client.ClientId));
            Assert.That(copy.ClientName, Is.EqualTo(client.ClientName));
            Assert.That(copy.Description, Is.EqualTo(client.Description));
            Assert.That(copy.Enabled, Is.EqualTo(client.Enabled));
            Assert.That(copy.RequirePkce, Is.EqualTo(client.RequirePkce));
            Assert.That(copy.RequireClientSecret, Is.EqualTo(client.RequireClientSecret));
            Assert.That(copy.AccessTokenType, Is.EqualTo(client.AccessTokenType));
            Assert.That(copy.AllowOfflineAccess, Is.EqualTo(client.AllowOfflineAccess));
            Assert.That(copy.SystemPermissionEnvironmentId, Is.EqualTo(client.SystemPermissionEnvironmentId));
            Assert.That(copy.AccessLevel, Is.EqualTo(client.AccessLevel));
            Assert.That(copy.AllowedGrantTypes, Is.EqualTo(client.AllowedGrantTypes));
            Assert.That(copy.RedirectUris, Is.EqualTo(client.RedirectUris));
            Assert.That(copy.AllowedCorsOrigins, Is.EqualTo(client.AllowedCorsOrigins));
            Assert.That(copy.ClientSecrets, Is.EqualTo(client.ClientSecrets));
            Assert.That(copy.AllowedScopes, Is.EqualTo(client.AllowedScopes));
            Assert.That(copy.Created, Is.EqualTo(client.Created));
            Assert.That(copy.Updated, Is.EqualTo(client.Updated));
        }
    }
}
