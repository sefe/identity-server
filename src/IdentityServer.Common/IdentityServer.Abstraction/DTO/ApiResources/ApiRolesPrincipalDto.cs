// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

using System.Text.Json.Serialization;
using IdentityServer.Abstraction.Entities.IdentityServerConfig;

namespace IdentityServer.Abstraction.DTO.ApiResources;

public class ApiRolesPrincipalDto
{
    [JsonConverter(typeof(JsonStringEnumConverter))]
    public required RoleMapType Type { get; set; }
    public required string Id { get; set; }
    public required string? Name { get; set; }
}
