// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

using System.ComponentModel.DataAnnotations;

namespace IdentityServer.Abstraction.DTO.ApiResources;

public abstract class ApiResourcePropertyBaseDtoCreate : IDtoCreate
{
    [Required]
    [Range(1, int.MaxValue, ErrorMessage = "API Resource Id must be a positive integer")]
    public int ApiResourceId { get; set; }
}
