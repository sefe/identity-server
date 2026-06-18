using IdentityServer.Data.Entities.Roles;

namespace IdentityServer.Data.Repositories.Storage;

internal class ApiResourceRoleParentAccessor : IParentAccessor<RoleMapping, ApiResourceRole>
{
    public int GetParentEnvironmentId(ApiResourceRole parent)
    {
        return parent.ApiResource?.SystemPermissionEnvironmentId
            ?? throw new InvalidOperationException($"Bug: API Resource navigation property is not populated by the Entity Framework!");
    }

    public int GetParentId(RoleMapping model)
    {
        return model.ApiResourceRoleId;
    }
}
