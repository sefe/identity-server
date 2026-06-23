// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

using System.ComponentModel.DataAnnotations;
using IdentityServer.Abstraction.Entities.IdentityServerConfig;
using IdentityServer.Abstraction.Entities.Validation;

namespace IdentityServer.Abstraction.DTO.Clients;

/// <summary>
/// All fields except Id are optional and nullable. Only fields to be updated must be set.
/// </summary>
public class ClientDtoUpdate : IDtoUpdate
{
    [Required]
    [Range(1, int.MaxValue, ErrorMessage = "Id must be a positive integer greater than 0")]
    public int Id { get; set; }

    [TrimmedStringLength(MaximumLength = Constants.Limits.Client.DisplayName.MaxLength, MinimumLength = 1, ErrorMessage = Constants.Limits.Client.DisplayName.MaxLengthError)]
    public string? ClientName { get; set; }

    [StringLength(Constants.Limits.Client.Description.MaxLength, ErrorMessage = Constants.Limits.Client.Description.MaxLengthError)]
    public string? Description { get; set; }

    public bool? Enabled { get; set; }
    public bool? RequirePkce { get; set; }
    public bool? RequireClientSecret { get; set; }
    public bool? AllowOfflineAccess { get; set; }

    [EnumDataType(typeof(ClientAccessTokenType))]
    [AllowedValues(null, ClientAccessTokenType.Jwt, ClientAccessTokenType.Reference, ErrorMessage = "Invalid Access Token Type value.")]
    public ClientAccessTokenType? AccessTokenType { get; set; }
}
