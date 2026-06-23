// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

using System.ComponentModel.DataAnnotations;
using IdentityServer.Abstraction.Entities.IdentityServerConfig;

namespace IdentityServer.Abstraction.DTO.Export;

public abstract class RoleMappingValueObject
{
    [Required]
    public abstract required string MappingType { get; set; }

    [Required]
    [StringLength(Constants.Limits.RoleMapping.Value.MaxLength, ErrorMessage = Constants.Limits.RoleMapping.Value.MaxLengthError)]
    public required string Value { get; set; }

    [StringLength(Constants.Limits.RoleMapping.Description.MaxLength, ErrorMessage = Constants.Limits.RoleMapping.Description.MaxLengthError)]
    public string? Description { get; set; } = default!;
}

public class EmptyRoleMappingValueObject : RoleMappingValueObject
{
    public static EmptyRoleMappingValueObject Instance { get => new() { MappingType = string.Empty, Value = string.Empty, Description = null }; }
    public override required string MappingType { get; set; }
}

public class ApiResourceRoleMappingValueObject : RoleMappingValueObject
{
    /// <summary>
    /// Values from <seealso cref="RoleMapType"/>
    /// </summary>
    [AllowedValues(nameof(RoleMapType.SecurityGroup), nameof(RoleMapType.UserObjectId), nameof(RoleMapType.ClientId), ErrorMessage = "Invalid Role Mapping Type Name. Allowed values are: SecurityGroup, UserObjectId, ClientId.")]
    public override required string MappingType { get; set; }
}

public class ClientRoleMappingValueObject : RoleMappingValueObject
{
    /// <summary>
    /// Values from <seealso cref="ClientRoleMapType"/>
    /// </summary>
    [AllowedValues(nameof(ClientRoleMapType.SecurityGroup), nameof(ClientRoleMapType.UserObjectId), ErrorMessage = "Invalid Client Role Mapping Type Name. Allowed values are: SecurityGroup, UserObjectId.")]
    public override required string MappingType { get; set; }
}
