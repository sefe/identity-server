using System.Linq.Expressions;
using System.Security.Claims;
using IdentityServer.Abstraction;
using IdentityServer.Abstraction.Contracts;
using IdentityServer.Abstraction.Entities.IdentityServerConfig.SystemPermissions;
using IdentityServer.Abstraction.Exceptions;
using IdentityServer.Abstraction.Extensions;

namespace IdentityServer.Data.Security;

/// <summary>
/// Responsible for general access security checks to system permission environments.
/// </summary>
public class StandardPermissionChecker : IPermissionChecker
{
    private readonly IStorage<SystemPermissionRole> _roleStorage;
    private readonly IStorage<SystemPermissionEnvironment> _envStorage;

    public StandardPermissionChecker(IStorage<SystemPermissionRole> roleStorage, IStorage<SystemPermissionEnvironment> envStorage)
    {
        _roleStorage = roleStorage;
        _envStorage = envStorage;
    }

    public async Task<HashSet<int>> GetAllAccessiblePermissionEnvironmentsAsync(ClaimsPrincipal user, SystemPermissionRoleType role)
    {
        if (user.IsInRole(Constants.RoleNames.Admin))
        {
            return (await _envStorage.ToListAsync(_ => true)).Select(e => e.Id).ToHashSet();
        }

        var userObjectId = user.GetUserObjectId();
        Expression<Func<SystemPermissionRole, bool>> itemsQuery = role switch
        {
            SystemPermissionRoleType.Reader => r => r.OId == userObjectId,
            SystemPermissionRoleType.Writer => r => r.OId == userObjectId && r.RoleType == role,
            _ => throw new NotImplementedException()
        };

        return (await _roleStorage.ToListAsync(itemsQuery)).Select(r => r.SystemPermissionEnvironmentId).ToHashSet();
    }

    public async Task<SystemPermissionRoleType> GetAccessRoleOrThrowIfNoAccessToEnvAsync(ClaimsPrincipal user, int permissionEnvId, EntityAccessType access, string itemTitle)
    {
        if (user.IsInRole(Constants.RoleNames.Admin))
        {
            return SystemPermissionRoleType.Writer;
        }

        var neededRole = access == EntityAccessType.Read ? SystemPermissionRoleType.Reader : SystemPermissionRoleType.Writer;

        var userObjectId = user.GetUserObjectId();

        // the best assignment a Reader role can have is Read.
        if (!user.IsInRole(Constants.RoleNames.User) && neededRole == SystemPermissionRoleType.Writer)
        {
            throw new EntityAccessException(user, itemTitle, access, $"Restricted system permission environment id: '{permissionEnvId}'.");
        }

        // get and check permissions for the user
        var permissions = await _roleStorage.ToListAsync(r => r.SystemPermissionEnvironmentId == permissionEnvId && r.OId == userObjectId);

        // Writer permission implicitly grants Reader access
        if (permissions.Any(r => r.RoleType == SystemPermissionRoleType.Writer))
        {
            return SystemPermissionRoleType.Writer;
        }

        if (permissions.Any(r => r.RoleType == neededRole))
        {
            return neededRole;
        }

        throw new EntityAccessException(user, itemTitle, access, $"Restricted system permission environment id: '{permissionEnvId}'.");
    }

    private static SystemPermissionRoleType GetAccessRoleToSystem(ClaimsPrincipal user, SystemPermission system, EntityAccessType access)
    {
        // Admin can read everything
        if (user.IsInRole(Constants.RoleNames.Admin)) { return SystemPermissionRoleType.Writer; }

        var userObjectId = user.GetUserObjectId();
        bool hasUserRole = user.IsInRole(Constants.RoleNames.User);
        var neededPermission = access == EntityAccessType.Read ? SystemPermissionRoleType.Reader : SystemPermissionRoleType.Writer;

        SystemPermissionRoleType actualPermission;
        if (hasUserRole) // User Role
        {
            actualPermission = EvaluateUserRoleSystemAccess(userObjectId, system);
        }
        else // Reader Role
        {
            // the best assignment a Reader role can have is Read.
            if (neededPermission == SystemPermissionRoleType.Writer)
            {
                actualPermission = SystemPermissionRoleType.None;
            }
            else
            {
                actualPermission = EvaluateReaderRoleSystemAccess(userObjectId, system);
            }
        }

        return actualPermission;
    }

    /// <inheritdoc/>
    public SystemPermissionRoleType GetAccessRoleOrThrowIfNoAccessToSystem(ClaimsPrincipal user, SystemPermission system, EntityAccessType access, string itemTitle)
    {
        var actualPermission = GetAccessRoleToSystem(user, system, access);

        var neededPermission = access == EntityAccessType.Read ? SystemPermissionRoleType.Reader : SystemPermissionRoleType.Writer;

        if (actualPermission < neededPermission)
        {
            throw new EntityAccessException(user, itemTitle, access, $"Restricted system permission id: '{system.Id}'.");
        }
        else
        {
            return actualPermission;
        }
    }

    private static SystemPermissionRoleType EvaluateReaderRoleSystemAccess(string userObjectId, SystemPermission system)
    {
        // any assignment in any env
        if (system.Environments.SelectMany(e => e.Permissions).Any(p => p.OId == userObjectId))
        {
            return SystemPermissionRoleType.Reader;
        }
        else
        {
            return SystemPermissionRoleType.None;
        }
    }

    private static SystemPermissionRoleType EvaluateUserRoleSystemAccess(string userObjectId, SystemPermission system)
    {
        var nonBlankEnvironments = system.Environments.Where(s => s.Permissions.Count > 0).ToList();

        // User has Full Writer to Blank System Permission
        if (nonBlankEnvironments.Count == 0) { return SystemPermissionRoleType.Writer; }

        // User role can be a stranger, reader, partial writer or full writer. For system permission partial writer must still return Reader.
        var assignments = nonBlankEnvironments.Select(e =>
        {
            var userPermissions = e.Permissions.Where(p => p.OId == userObjectId).ToList();
            if (userPermissions.Count > 0) { return userPermissions.Max(p => p.RoleType); }
            else { return SystemPermissionRoleType.None; }
        }).ToList();

        // Full writer access -> Writer
        if (assignments.All(p => p == SystemPermissionRoleType.Writer))
        {
            return SystemPermissionRoleType.Writer;
        }

        // Partial writer access -> reader; None otherwise
        return assignments.Any(p => p > SystemPermissionRoleType.None)
            ? SystemPermissionRoleType.Reader
            : SystemPermissionRoleType.None;
    }
}
