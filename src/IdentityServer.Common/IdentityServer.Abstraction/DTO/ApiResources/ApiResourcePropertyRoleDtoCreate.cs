// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

using System.ComponentModel.DataAnnotations;

namespace IdentityServer.Abstraction.DTO.ApiResources;

public class ApiResourcePropertyRoleDtoCreate : ApiResourcePropertyBaseDtoCreate
{
    [Required]
    [StringLength(Constants.Limits.Role.Name.MaxLength, ErrorMessage = Constants.Limits.Role.Name.MaxLengthError, MinimumLength = 1)]
    [RegularExpression(Constants.Limits.Role.Name.Pattern, ErrorMessage = Constants.Limits.Role.Name.PatternError)]
    [Display(Name = "Role Name")]
    public string RoleName { get; set; } = default!;
}
