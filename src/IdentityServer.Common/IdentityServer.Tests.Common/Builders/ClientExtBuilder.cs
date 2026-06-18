using Duende.IdentityServer.EntityFramework.Entities;
using IdentityServer.Abstraction.Entities.IdentityServerConfig.SystemPermissions;
using IdentityServer.Data.DuendeEntityExtensions;
using IdentityServer.Data.Entities.Roles;

namespace IdentityServer.Tests.Common.Builders;

public class ClientExtBuilder
{
    private readonly ClientExt _client;
    public ClientExtBuilder(string clientId, string clientName)
    {
        _client = new ClientExt
        {
            ClientId = clientId,
            ClientName = clientName,
            SystemPermissionEnvironment = new SystemPermissionEnvironment
            {
                Environment = SystemPermissionEnvironmentNames.Development,
                SystemPermission = new SystemPermission
                {
                    Name = "Default System Permission",
                    Description = "Default System Permission for testing purposes"
                }
            },
            ClientSecrets = new List<ClientSecret>(),
            RedirectUris = new List<ClientRedirectUri>(),
            AllowedCorsOrigins = new List<ClientCorsOrigin>(),
            AllowedGrantTypes = new List<ClientGrantType>(),
            AllowedScopes = new List<ClientScope>()
        };
    }

    public ClientExtBuilder WithId(int id)
    {
        _client.Id = id;
        return this;
    }

    public ClientExtBuilder WithRole(string roleName, List<ClientRoleMapping> mappings)
    {
        var role = new ClientRole
        {
            RoleName = roleName,
            Mappings = mappings
        };
        _client.Roles.Add(role);
        return this;
    }

    public ClientExtBuilder WithSecret(string description)
    {
        var secret = new ClientSecretExt
        {
            Description = description,
            Value = "test-secret-value"
        };
        _client.ClientSecrets.Add(secret);
        return this;
    }

    public ClientExtBuilder WithScope(string scopeName)
    {
        var scope = new ClientScopeExt
        {
            Scope = scopeName
        };
        _client.AllowedScopes.Add(scope);
        return this;
    }

    public ClientExtBuilder WithRedirectUri(string uri)
    {
        var redirectUri = new ClientRedirectUriExt
        {
            RedirectUri = uri
        };
        _client.RedirectUris.Add(redirectUri);
        return this;
    }

    public ClientExtBuilder WithGrantType(string grantType)
    {
        var clientGrantType = new ClientGrantTypeExt
        {
            GrantType = grantType
        };
        _client.AllowedGrantTypes.Add(clientGrantType);
        return this;
    }

    public ClientExtBuilder WithCorsOrigin(string origin)
    {
        var corsOrigin = new ClientCorsOriginExt
        {
            Origin = origin
        };
        _client.AllowedCorsOrigins.Add(corsOrigin);
        return this;
    }

    public ClientExtBuilder WithEntraApp(string appId, string appName)
    {
        var entraApp = new ClientEntraApp
        {
            AppId = appId,
            AppName = appName
        };
        _client.EntraApps.Add(entraApp);
        return this;
    }

    public ClientExt Build()
    {
        return _client;
    }
}
