// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

using System.Security.Claims;
using IdentityServer.Abstraction.Entities.IdentityServerConfig.SystemPermissions;
using IdentityServer.Abstraction.Exceptions;

namespace IdentityServer.Abstraction.Contracts;

public interface IPermissionChecker
{
    /// <summary>
    /// Checks user access level in the specific System Permission.
    /// </summary>
    /// <param name="user">User</param>
    /// <param name="system">System Permission to check access to</param>
    /// <param name="access">The kind of access needed for the operation</param>
    /// <param name="itemTitle">The details of the operation the user is trying to perform</param>
    /// <returns><seealso cref="SystemPermissionRoleType.Writer"/> if the user has admin-level access to the system permission (FULL WRITER).
    /// <seealso cref="SystemPermissionRoleType.Reader"/> is the user has read-only access to the system permission.
    /// <seealso cref="SystemPermissionRoleType.None"/> otherwise.</returns>
    /// <exception cref="EntityAccessException">Thrown when the user access level is not enough to perform the requested operation.</exception>
    SystemPermissionRoleType GetAccessRoleOrThrowIfNoAccessToSystem(ClaimsPrincipal user, SystemPermission system, EntityAccessType access, string itemTitle);
    /// <summary>
    /// Checks user access level in the specific System Permission. Throws if no access.
    /// </summary>
    /// <param name="user">User</param>
    /// <param name="system">System Permission to check access to</param>
    /// <param name="access">The kind of access needed for the operation</param>
    /// <param name="itemTitle">Human-readable title of the item the user is trying to access.</param>
    /// <returns><seealso cref="SystemPermissionRoleType.Writer"/> if the user has admin-level access to the system permission (FULL WRITER).
    /// <seealso cref="SystemPermissionRoleType.Reader"/> is the user has read-only access to the system permission.
    /// <seealso cref="SystemPermissionRoleType.None"/> otherwise.</returns>
    Task<SystemPermissionRoleType> GetAccessRoleOrThrowIfNoAccessToEnvAsync(ClaimsPrincipal user, int permissionEnvId, EntityAccessType access, string itemTitle);
    /// <summary>
    /// Retrieves a set of environment IDs that the specified user has access to, based on their role.
    /// </summary>
    /// <param name="user">The user whose permissions are being evaluated. Cannot be <see langword="null"/>.</param>
    /// <param name="role">The role used to determine the user's access permissions.</param>
    /// <returns>A <see cref="HashSet{int}"/> of environment IDs the user has access to.
    /// The set will be empty if no environments are accessible.</returns>
    Task<HashSet<int>> GetAllAccessiblePermissionEnvironmentsAsync(ClaimsPrincipal user, SystemPermissionRoleType role);
}
