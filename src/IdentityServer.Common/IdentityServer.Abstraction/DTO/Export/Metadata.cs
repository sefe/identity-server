// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

namespace IdentityServer.Abstraction.DTO.Export;

public class DtoMetadata
{
    public CreatedDtoMetadata Created { get; set; } = new();
    public EntityDtoMetadata Entity { get; set; } = new();
    public EnvironmentDtoMetadata Environment { get; set; } = new();
}

public class EntityDtoMetadata
{
    public string? Type { get; set; }
    public int? Id { get; set; }
    public string? Name { get; set; }
    public string? DisplayName { get; set; }
    public string? SystemPermissionName { get; set; }
    public string? SystemPermissionEnvironmentName { get; set; }
    public DateTime? LastModified { get; set; }
}

public class EnvironmentDtoMetadata
{
    public string? Name { get; set; }
}

public class CreatedDtoMetadata
{
    public string? CreatedById { get; set; }
    public string? CreatedByName { get; set; }
    public DateTime? CreatedAt { get; set; }
}
