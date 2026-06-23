// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

using System.ComponentModel.DataAnnotations;
using IdentityServer.Abstraction.Entities.Validation;

namespace IdentityServer.Abstraction.DTO.Export;

public class RoleExportDto<TRoleMapping> where TRoleMapping : RoleMappingValueObject
{
    public DtoMetadata Metadata { get; set; } = new();

    [Required]
    [NotEmpty(ErrorMessage = "At least one Role must be provided.")]
    public List<RoleValueObject<TRoleMapping>> Roles { get; set; } = new();
}
