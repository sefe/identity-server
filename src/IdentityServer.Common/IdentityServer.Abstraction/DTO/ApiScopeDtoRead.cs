// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

namespace IdentityServer.Abstraction.DTO;

public class ApiScopeDtoRead : IDtoRead
{
    public int Id { get; set; }
    public bool Enabled { get; set; }
    public required string Name { get; set; }
    public required string DisplayName { get; set; }
    public string? Description { get; set; }
    public bool Required { get; set; }
    public DateTime Created { get; set; }
    public DateTime? Updated { get; set; }
    public int ClientCount { get; set; }
}
