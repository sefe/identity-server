// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

using IdentityServer.Abstraction.DTO.Export;
using IdentityServer.Abstraction.DTO.Import;

namespace IdentityServer.AdminPortal.Web.Models.RoleImport;

public class ClientRoleImportModel : ImportRoleModel<ClientRoleImportDto, ClientRoleMappingValueObject>
{
    public override OperationStatus<ClientRoleImportDto> FileParsingStatus { get; set; } = new OperationStatus<ClientRoleImportDto> { Result = new() };
}
