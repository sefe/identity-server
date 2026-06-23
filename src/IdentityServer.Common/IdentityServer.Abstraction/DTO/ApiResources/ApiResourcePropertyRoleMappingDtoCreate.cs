// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

using System.ComponentModel.DataAnnotations;
using IdentityServer.Abstraction.Entities.IdentityServerConfig;

namespace IdentityServer.Abstraction.DTO.ApiResources;

public class ApiResourcePropertyRoleMappingDtoCreate : ApiResourcePropertyBaseDtoCreate
{
    [Required]
    [Range(1, int.MaxValue, ErrorMessage = "API Resource Role Id must be a positive integer")]
    public int ApiResourceRoleId { get; set; }

    [EnumDataType(typeof(RoleMapType))]
    [AllowedValues(RoleMapType.SecurityGroup, RoleMapType.UserObjectId, RoleMapType.ClientId, ErrorMessage = "Invalid Role Mapping Type.")]
    public RoleMapType MappingType { get; set; }

    [Required]
    [StringLength(Constants.Limits.RoleMapping.Value.MaxLength, ErrorMessage = Constants.Limits.RoleMapping.Value.MaxLengthError, MinimumLength = 1)]
    public required string Value { get; set; }
}
