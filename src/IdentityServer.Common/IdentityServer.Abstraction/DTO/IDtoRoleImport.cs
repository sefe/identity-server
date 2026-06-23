// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

using IdentityServer.Abstraction.DTO.Export;
using IdentityServer.Abstraction.DTO.Import;

namespace IdentityServer.Abstraction.DTO;

public interface IDtoRoleImport<TRoleMapping> : IDtoImport where TRoleMapping : RoleMappingValueObject
{
    public DtoMetadata Metadata { get; set; }
    public List<RoleValueObject<TRoleMapping>> Roles { get; set; }
    public ImportStrategy ImportStrategy { get; set; }
}
