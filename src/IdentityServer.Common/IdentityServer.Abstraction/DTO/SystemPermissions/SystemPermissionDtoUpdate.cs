// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

using System.ComponentModel.DataAnnotations;

namespace IdentityServer.Abstraction.DTO.SystemPermissions;

public class SystemPermissionDtoUpdate : IDtoUpdate
{
    [Required]
    [Range(1, int.MaxValue, ErrorMessage = "Id must be a positive integer greater than 0")]
    public int Id { get; set; }

    [Required]
    [StringLength(Constants.Limits.SystemPermission.Description.MaxLength, ErrorMessage = Constants.Limits.SystemPermission.Description.MaxLengthError)]
    public required string Description { get; set; }
}
