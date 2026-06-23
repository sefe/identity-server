// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

using System.ComponentModel.DataAnnotations;

namespace IdentityServer.Abstraction.DTO.Clients;

public class ClientPropertySecretDtoCreate : ClientPropertyBaseDtoCreate
{
    [Required]
    [StringLength(Constants.Limits.Secret.Description.MaxLength, ErrorMessage = Constants.Limits.Secret.Description.MaxLengthError)]
    public required string Description { get; set; }

    [Required]
    [Range(1, 99, ErrorMessage = "Validity period must be between 1 and 99 years.")]
    public int ValidityPeriodYears { get; set; }
}
