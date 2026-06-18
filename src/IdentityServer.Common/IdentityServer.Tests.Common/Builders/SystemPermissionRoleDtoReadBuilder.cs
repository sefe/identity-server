using IdentityServer.Abstraction.DTO.SystemPermissions;
using IdentityServer.Abstraction.Entities.IdentityServerConfig.SystemPermissions;

namespace IdentityServer.Tests.Common.Builders;

public class SystemPermissionRoleDtoReadBuilder
{
    private static int _uniqueIdCounter = 0;

    private readonly SystemPermissionRoleDtoRead _role;

    public SystemPermissionRoleDtoReadBuilder(int environmentId, string oId, string name, SystemPermissionRoleType roleType)
    {
        _role = new SystemPermissionRoleDtoRead
        {
            Id = Interlocked.Increment(ref _uniqueIdCounter),
            OId = oId,
            Name = name,
            SystemPermissionEnvironmentId = environmentId,
            RoleType = roleType
        };
    }

    public SystemPermissionRoleDtoRead Build()
    {
        return _role;
    }
}
