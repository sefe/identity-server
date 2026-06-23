// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

using System.ComponentModel.DataAnnotations;

namespace IdentityServer.Abstraction.DTO.ApiResources;

public class ApiRolesReportRequest
{
    [Required]
    public required string ApiResourceName { get; set; }

    /// <summary>
    /// Role to generate report for. All roles will be returned if not specified.
    /// </summary>
    public string? Role { get; set; }

    [AllowedValues(null, nameof(Entities.IdentityServerConfig.RoleMapType.SecurityGroup), nameof(Entities.IdentityServerConfig.RoleMapType.UserObjectId), nameof(Entities.IdentityServerConfig.RoleMapType.ClientId), ErrorMessage = "Invalid Role Mapping Type. Valid values are: UserObjectId, SecurityGroup, ClientId")]
    /// <summary>
    /// Assignments type to include in report.
    /// </summary>
    public string? RoleMapType { get; set; }
}
