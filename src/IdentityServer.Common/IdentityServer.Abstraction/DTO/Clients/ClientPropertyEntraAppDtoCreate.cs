// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

using System.ComponentModel.DataAnnotations;
using IdentityServer.Abstraction.Entities.Validation;

namespace IdentityServer.Abstraction.DTO.Clients;

public class ClientPropertyEntraAppDtoCreate : ClientPropertyBaseDtoCreate
{
    [Required]
    [ValidGuid]
    public required string AppId { get; set; }
}
