// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

using IdentityServer.Abstraction.DTO.SystemPermissions;
using IdentityServer.Abstraction.Entities.IdentityServerConfig.SystemPermissions;

namespace IdentityServer.AdminPortal.Web.Services;

public class SystemOwnerService : ISystemOwnerService
{
    private readonly IConfirmationService _confirmationService;
    private readonly IAdminApiService _adminApi;

    public SystemOwnerService(IConfirmationService confirmationService, IAdminApiService adminApi)
    {
        _confirmationService = confirmationService;
        _adminApi = adminApi;
    }

    public Task ShowContactsPopup(SystemPermissionShortDtoRead sysPermission)
    {
        return _confirmationService.ConfirmAsync("System Permission Owners", GetOwnersMessage("System Permission", sysPermission.Owners), false);
    }

    public Task ShowContactsPopup(SystemPermissionEnvironmentDtoRead sysPermissionEnvironment)
    {
        return _confirmationService.ConfirmAsync("System Permission Environment Owners", GetOwnersMessage("System Permission Environment", sysPermissionEnvironment.Owners), false);
    }

    public async Task ShowContactsPopup(int envId)
    {
        await _confirmationService.ConfirmAsync("System Permission Environment Owners", GetOwnersMessage("System Permission Environment", await GetOwners(envId)), false);
    }

    private async Task<string> GetOwners(int envId)
    {
        var owners = await _adminApi.GetSystemPermissionEnvironmentContacts(envId);
        if (owners.Result?.Length > 0)
        {
            return string.Join(", ", owners.Result);
        }
        return string.Empty;
    }

    public async Task<bool> CheckUserAssignmentRemovalConditions(SystemPermissionDtoRead systemPermission, SystemPermissionEnvironmentDtoRead roleEnvironment, SystemPermissionRoleDtoRead role)
    {
        return role.RoleType switch
        {
            SystemPermissionRoleType.None => true,
            SystemPermissionRoleType.Reader => await CheckUserSimpleAssignmentRemovalConditions(systemPermission, roleEnvironment, role),
            SystemPermissionRoleType.Writer => await CheckUserWriterAssignmentRemovalConditions(systemPermission, roleEnvironment, role),
            _ => throw new InvalidOperationException($"Unsupported role type '{role.RoleType}'"),
        };
    }

    internal async Task<bool> CheckUserWriterAssignmentRemovalConditions(SystemPermissionDtoRead systemPermission, SystemPermissionEnvironmentDtoRead roleEnvironment, SystemPermissionRoleDtoRead role)
    {
        if (UserIsFullWriter(systemPermission, role.OId)) // a Full Writer's assignment is about to be deleted
        {
            if (IsLastFullWriter(systemPermission)) // Block last Full Writer removal
            {
                await _confirmationService.ConfirmAsync(FullWriterLastDeletionBlock.Title,
                    FullWriterLastDeletionBlock.FormatMessage(role.Name), false);
                return false;
            }
            else // There are other Full Writers, proceed with deletion confirmation
            {
                return await _confirmationService.ConfirmAsync(FullWriterDeletionConfirmation.Title,
                    FullWriterDeletionConfirmation.FormatMessage(role.Name, systemPermission.Name));
            }
        }

        return await CheckUserSimpleAssignmentRemovalConditions(systemPermission, roleEnvironment, role);
    }

    internal async Task<bool> CheckUserSimpleAssignmentRemovalConditions(SystemPermissionDtoRead systemPermission, SystemPermissionEnvironmentDtoRead roleEnvironment, SystemPermissionRoleDtoRead role)
    {
        if (IsLastAssignmentInSystemPermission(systemPermission, role.OId)) // User is about to lose access to the system permission
        {
            return await _confirmationService.ConfirmAsync(UserSystemPermissionAccessRemovalConfirmation.Title,
                UserSystemPermissionAccessRemovalConfirmation.FormatMessage(role, systemPermission.Name));
        }
        else // User is about to lose access to the environment
        {
            return await _confirmationService.ConfirmAsync(UserSystemPermissionEnvironmentAccessRemovalConfirmation.Title,
                UserSystemPermissionEnvironmentAccessRemovalConfirmation.FormatMessage(role, roleEnvironment.Environment));
        }
    }

    private static bool UserHasAccess(SystemPermissionEnvironmentDtoRead systemPermissionEnvironment, string userObjectId, SystemPermissionRoleType roleType)
    {
        return systemPermissionEnvironment.Permissions.Any(p => p.OId == userObjectId && p.RoleType == roleType);
    }

    private static bool UserIsFullWriter(SystemPermissionDtoRead systemPermission, string userObjectId)
    {
        return systemPermission?.Environments == null || systemPermission.Environments.Count == 0 || systemPermission.Environments.Where(e => e.Permissions.Count > 0)
            .All(spe => UserHasAccess(spe, userObjectId, SystemPermissionRoleType.Writer));
    }

    private static bool IsLastFullWriter(SystemPermissionDtoRead systemPermission)
    {
        if (systemPermission?.Environments == null || systemPermission.Environments.Count == 0)
        {
            return false;
        }

        return systemPermission.Environments
            .Where(e => e?.Permissions != null)
            .SelectMany(e => e.Permissions)
            .Where(p => p.RoleType == SystemPermissionRoleType.Writer)
            .GroupBy(p => p.OId)
            .Count(g => g.Count() == systemPermission.Environments.Count) == 1;
    }

    private static bool IsLastAssignmentInSystemPermission(SystemPermissionDtoRead systemPermission, string userObjectId)
    {
        if (systemPermission?.Environments == null || systemPermission.Environments.Count == 0)
        {
            return false;
        }

        return systemPermission.Environments
            .Where(e => e?.Permissions != null)
            .SelectMany(e => e.Permissions)
            .Count(p => p.OId == userObjectId) == 1;
    }

    private static string GetOwnersMessage(string itemTitle, string owners)
    {
        return string.IsNullOrEmpty(owners) ?
            $"The access to this {itemTitle} can only be granted by IdentityServer support personnel."
            : $"Access to this {itemTitle} can be granted by: " + owners;
    }

    public static readonly Message<string> FullWriterLastDeletionBlock = new()
    {
        Title = "Warning!",
        FormatMessage = userName => $"Unable to delete the user '{userName}' assignment because this is the only user who can manage this system permission. Please assign another user as Writer to all environments first."
    };

    public static readonly Message<string, string> FullWriterDeletionConfirmation = new()
    {
        Title = "System Permission Owner Removal Confirmation",
        FormatMessage = (userName, systemPermissionName) => $"The user '{userName}' can manage all environments of the system permission '{systemPermissionName}'. Once you remove their access, they will be able to manage the assigned environments only."
    };

    public static readonly Message<SystemPermissionRoleDtoRead, string> UserSystemPermissionAccessRemovalConfirmation = new()
    {
        Title = "System Permission Lock-Out Confirmation",
        FormatMessage = (role, systemPermissionName) => $"The user '{role.Name}' will no longer have '{role.RoleType}' access to the system permission '{systemPermissionName}'."
    };

    public static readonly Message<SystemPermissionRoleDtoRead, string> UserSystemPermissionEnvironmentAccessRemovalConfirmation = new()
    {
        Title = "Environment Lock-Out Confirmation",
        FormatMessage = (role, environmentName) => $"The user '{role.Name}' will no longer have '{role.RoleType}' access to the system permission environment '{environmentName}'."
    };

    public class Message<T1>
    {
        public required string Title { get; set; }
        public required Func<T1, string> FormatMessage { get; set; }
    }

    public class Message<T1, T2>
    {
        public required string Title { get; set; }
        public required Func<T1, T2, string> FormatMessage { get; set; }
    }
}
