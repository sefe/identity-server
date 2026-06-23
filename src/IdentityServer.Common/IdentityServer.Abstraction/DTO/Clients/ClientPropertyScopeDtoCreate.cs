// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

using System.ComponentModel.DataAnnotations;

namespace IdentityServer.Abstraction.DTO.Clients;

public class ClientPropertyScopeDtoCreate : ClientPropertyBaseDtoCreate
{
    [Required]
    [StringLength(200, ErrorMessage = "Scope cannot exceed 200 characters.")]
    public required string Scope { get; set; }
}
