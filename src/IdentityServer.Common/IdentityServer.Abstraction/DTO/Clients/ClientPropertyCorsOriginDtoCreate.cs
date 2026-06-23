// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

using System.ComponentModel.DataAnnotations;
using IdentityServer.Abstraction.Entities.Validation;

namespace IdentityServer.Abstraction.DTO.Clients;

public class ClientPropertyCorsOriginDtoCreate : ClientPropertyBaseDtoCreate
{
    [Required]
    [StringLength(150, ErrorMessage = "CORS origin cannot exceed 150 characters.")]
    [ClientCorsOriginValidation]
    public required string Origin { get; set; }
}
