// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

using IdentityServer.Abstraction.Entities.IdentityServerConfig.SystemPermissions;

namespace IdentityServer.Abstraction.DTO.SystemPermissions;

public class SystemPermissionRoleDtoRead : IDtoRead
{
    public int Id { get; set; }
    public required string OId { get; set; }
    public required string Name { get; set; }
    public int SystemPermissionEnvironmentId { get; set; }
    public SystemPermissionRoleType RoleType { get; set; }
}