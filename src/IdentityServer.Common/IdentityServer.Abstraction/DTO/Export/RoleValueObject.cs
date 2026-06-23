// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

using System.ComponentModel.DataAnnotations;

namespace IdentityServer.Abstraction.DTO.Export;

public class RoleValueObject<TRoleMapping> where TRoleMapping : RoleMappingValueObject
{
    [Required]
    [StringLength(Constants.Limits.Role.Name.MaxLength, ErrorMessage = Constants.Limits.Role.Name.MaxLengthError)]
    [RegularExpression(Constants.Limits.Role.Name.Pattern, ErrorMessage = Constants.Limits.Role.Name.PatternError)]
    public required string RoleName { get; set; }

    [Required]
    public required List<TRoleMapping> Mappings { get; set; } = new();
}
