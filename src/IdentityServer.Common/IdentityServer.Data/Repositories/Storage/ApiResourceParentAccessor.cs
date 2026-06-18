using IdentityServer.Data.DuendeEntityExtensions;
using IdentityServer.Data.Entities.Roles;

namespace IdentityServer.Data.Repositories.Storage;

internal class ApiResourceParentAccessor :
    IParentAccessor<ApiResourceScopeExt, ApiResourceExt>,
    IParentAccessor<ApiResourceSecretExt, ApiResourceExt>,
    IParentAccessor<ApiResourceRole, ApiResourceExt>
{
    public int GetParentEnvironmentId(ApiResourceExt parent)
    {
        return parent.SystemPermissionEnvironmentId;
    }

    public int GetParentId(ApiResourceScopeExt model)
    {
        return model.ApiResourceId;
    }

    public int GetParentId(ApiResourceSecretExt model)
    {
        return model.ApiResourceId;
    }

    public int GetParentId(ApiResourceRole model)
    {
        return model.ApiResourceId;
    }
}
