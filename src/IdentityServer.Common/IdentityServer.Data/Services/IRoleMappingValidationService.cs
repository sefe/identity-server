// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

using IdentityServer.Abstraction.DTO.Export;
using IdentityServer.Abstraction.DTO.Import;
using IdentityServer.Data.Entities.Roles;

namespace IdentityServer.Data.Services;

public interface IRoleMappingValidationService
{
    Task<OperationStatus> ValidateApiRoleMappingAsync(RoleMapping resource);
    Task<OperationStatus> ValidateClientRoleMappingAsync(ClientRoleMapping resource);
    Task ValidateImportRoleMappingsAsync(List<RoleMappingValueObject> roleMappings, OperationStatus status);
}
