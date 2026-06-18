using Duende.IdentityServer;
using Duende.IdentityServer.EntityFramework.Mappers;
using Duende.IdentityServer.Models;

namespace IdentityServer.Data.Test.Data;

internal static class DummyClients
{
    internal static Duende.IdentityServer.EntityFramework.Entities.Client FetchClientEntity(string clientName)
    {
        var identityServerClientModel = new Client()
        {
            ClientName = clientName,
            ClientId = "identityserver.admin.test",
            AllowedGrantTypes = GrantTypes.Code,
            AccessTokenType = AccessTokenType.Jwt,
            AllowOfflineAccess = true,
            EnableLocalLogin = false,
            UpdateAccessTokenClaimsOnRefresh = true,
            RedirectUris =
            {
                "https://localhost:7189/signin-oidc"
            },
            PostLogoutRedirectUris =
            {
                "https://localhost:7189/signout-callback-oidc"
            },
            AllowedScopes =
            {
                IdentityServerConstants.StandardScopes.OpenId,
                IdentityServerConstants.StandardScopes.Profile,
                "roles",
                "email",
                "identityserver.api"
            },
            ClientSecrets =
            {
                new Secret("secret".Sha256())
            },
            RequireConsent = false
        };

        Duende.IdentityServer.EntityFramework.Entities.Client client = identityServerClientModel.ToEntity();
        return client;
    }

    internal static Duende.IdentityServer.EntityFramework.Entities.ApiResource FetchApiResourceEntity(string name)
    {

        var resource = new ApiResource(name, "Identity Server Admin API", new List<string> { "role" })
        {
            Scopes =
            {
                "identityserver.admin"
            },
            ApiSecrets = { new Secret("9C696CCD-DCC2-46F3-83EA-D8B9803C3C80".Sha256()) }
        };

        var apiEntityResource = resource.ToEntity();
        return apiEntityResource;
    }
}
