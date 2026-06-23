// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

using IdentityServer.Abstraction.DTO.SystemPermissions;

namespace IdentityServer.AdminPortal.Web.Services;
public interface ISystemOwnerService
{
    Task ShowContactsPopup(int envId);
    Task ShowContactsPopup(SystemPermissionShortDtoRead sysPermission);
    Task ShowContactsPopup(SystemPermissionEnvironmentDtoRead sysPermissionEnvironment);
    Task<bool> CheckUserAssignmentRemovalConditions(SystemPermissionDtoRead systemPermission, SystemPermissionEnvironmentDtoRead roleEnvironment, SystemPermissionRoleDtoRead role);
}
