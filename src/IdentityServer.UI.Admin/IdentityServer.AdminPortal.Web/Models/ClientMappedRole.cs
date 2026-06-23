// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

using IdentityServer.Abstraction.DTO.Clients;

namespace IdentityServer.AdminPortal.Web.Models;

public class ClientMappedRole
{
    public int ClientRoleId { get; set; }
    public required string ClientRoleName { get; set; }
    public required ClientPropertyRoleMappingDtoRead RoleMapping { get; set; }

    public string RoleMappingValue => RoleMapping.Value;
    public string? RoleMappingDescription => RoleMapping.Description;
}
