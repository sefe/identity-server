// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

using System.ComponentModel.DataAnnotations;
using IdentityServer.Abstraction.Entities.IdentityServerConfig.SystemPermissions;

namespace IdentityServer.Abstraction.DTO.SystemPermissions;

public class SystemPermissionRoleDtoCreate : IDtoCreate
{
    [Required]
    [StringLength(36, MinimumLength = 36)]
    public string OId { get; set; } = default!;

    [Required]
    [Range(1, int.MaxValue, ErrorMessage = "The System Permission Environment ID value is invalid.")]
    public int SystemPermissionEnvironmentId { get; set; }

    [EnumDataType(typeof(SystemPermissionRoleType))]
    [AllowedValues(SystemPermissionRoleType.Reader, SystemPermissionRoleType.Writer, ErrorMessage = "Invalid System Permission Role.")]
    public SystemPermissionRoleType RoleType { get; set; }
}
