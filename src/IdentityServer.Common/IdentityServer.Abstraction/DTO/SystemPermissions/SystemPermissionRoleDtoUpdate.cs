// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

using System.ComponentModel.DataAnnotations;
using IdentityServer.Abstraction.Entities.IdentityServerConfig.SystemPermissions;

namespace IdentityServer.Abstraction.DTO.SystemPermissions;

public class SystemPermissionRoleDtoUpdate : IDtoUpdate
{
    [Required]
    [Range(1, int.MaxValue, ErrorMessage = "Id must be a positive integer greater than 0")]
    public int Id { get; set; }

    [Required]
    [StringLength(36)]
    public required string OId { get; set; }

    [EnumDataType(typeof(SystemPermissionRoleType))]
    [AllowedValues(SystemPermissionRoleType.Reader, SystemPermissionRoleType.Writer, ErrorMessage = "Invalid System Permission Role.")]
    public SystemPermissionRoleType RoleType { get; set; }
}