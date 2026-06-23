// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

namespace IdentityServer.Abstraction.DTO.ApiResources;

public class ApiRolesAssignmentsDto
{
    public required string ApiResourceName { get; set; }
    public required Dictionary<string, List<ApiRolesPrincipalDto>> Assignments { get; set; }
}
