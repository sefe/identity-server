// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

using System.ComponentModel.DataAnnotations;
using IdentityServer.Abstraction.DTO.Export;

namespace IdentityServer.Abstraction.DTO.Import;

public class ClientRoleImportDto : RoleExportDto<ClientRoleMappingValueObject>, IDtoRoleImport<ClientRoleMappingValueObject>
{
    [Required]
    [AllowedValues(ImportStrategy.Replace, ImportStrategy.Add)]
    public ImportStrategy ImportStrategy { get; set; }
}
