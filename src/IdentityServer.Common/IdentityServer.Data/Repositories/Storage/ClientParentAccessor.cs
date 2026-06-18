using IdentityServer.Data.DuendeEntityExtensions;
using IdentityServer.Data.Entities.Roles;

namespace IdentityServer.Data.Repositories.Storage;

internal class ClientParentAccessor :
    IParentAccessor<ClientCorsOriginExt, ClientExt>,
    IParentAccessor<ClientGrantTypeExt, ClientExt>,
    IParentAccessor<ClientEntraApp, ClientExt>,
    IParentAccessor<ClientRedirectUriExt, ClientExt>,
    IParentAccessor<ClientPostLogoutRedirectUriExt, ClientExt>,
    IParentAccessor<ClientRole, ClientExt>,
    IParentAccessor<ClientScopeExt, ClientExt>,
    IParentAccessor<ClientSecretExt, ClientExt>
{
    public int GetParentEnvironmentId(ClientExt parent)
    {
        return parent.SystemPermissionEnvironmentId;
    }

    public int GetParentId(ClientCorsOriginExt model)
    {
        return model.ClientId;
    }

    public int GetParentId(ClientGrantTypeExt model)
    {
        return model.ClientId;
    }

    public int GetParentId(ClientEntraApp model)
    {
        return model.ClientId;
    }

    public int GetParentId(ClientRedirectUriExt model)
    {
        return model.ClientId;
    }

    public int GetParentId(ClientPostLogoutRedirectUriExt model)
    {
        return model.ClientId;
    }

    public int GetParentId(ClientScopeExt model)
    {
        return model.ClientId;
    }

    public int GetParentId(ClientSecretExt model)
    {
        return model.ClientId;
    }

    public int GetParentId(ClientRole model)
    {
        return model.ClientId;
    }
}
