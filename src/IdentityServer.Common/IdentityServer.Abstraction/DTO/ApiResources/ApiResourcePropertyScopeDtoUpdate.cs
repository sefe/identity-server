// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

using System.ComponentModel.DataAnnotations;
using IdentityServer.Abstraction.Entities.Validation;

namespace IdentityServer.Abstraction.DTO.ApiResources;

/// <summary>
/// All fields except Id are optional and nullable. Only fields to be updated must be set.
/// </summary>
public class ApiResourcePropertyScopeDtoUpdate : IDtoUpdate
{
    [Required]
    [Range(1, int.MaxValue, ErrorMessage = "Id must be a positive integer greater than 0")]
    public int Id { get; set; }

    [TrimmedStringLength(MaximumLength = Constants.Limits.ApiScope.DisplayName.MaxLength, MinimumLength = 1, ErrorMessage = Constants.Limits.ApiScope.DisplayName.LengthRangeError)]
    public string? DisplayName { get; set; }

    [StringLength(Constants.Limits.ApiScope.Description.MaxLength, ErrorMessage = Constants.Limits.ApiScope.Description.MaxLengthError)]
    public string? Description { get; set; }
    public bool? Enabled { get; set; }
    public bool? Required { get; set; }
}
