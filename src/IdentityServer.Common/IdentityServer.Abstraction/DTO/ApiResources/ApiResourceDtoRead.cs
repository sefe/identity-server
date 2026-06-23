// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

using IdentityServer.Abstraction.Contracts;
using IdentityServer.Abstraction.Entities.IdentityServerConfig;
using IdentityServer.Abstraction.Entities.IdentityServerConfig.SystemPermissions;

namespace IdentityServer.Abstraction.DTO.ApiResources;

public class ApiResourceDtoRead : IDtoRead, IHasEnvironment
{
    public int Id { get; set; }
    public bool Enabled { get; set; }
    public string Name { get; set; } = default!;
    public string DisplayName { get; set; } = default!;
    public string? Description { get; set; }
    public List<ApiResourcePropertyRoleDtoRead> Roles { get; set; } = new();
    public List<ApiResourcePropertySecretDtoRead> Secrets { get; set; } = new();
    public List<ApiResourcePropertyScopeDtoRead> Scopes { get; set; } = new();
    public DateTime Created { get; set; }
    public DateTime? Updated { get; set; }
    public string? UpdateReason { get; set; }
    public int SystemPermissionId { get; set; }
    public string SystemPermissionName { get; set; } = string.Empty;
    public int SystemPermissionEnvironmentId { get; set; }
    public string SystemPermissionEnvironmentName { get; set; } = string.Empty;
    public SystemPermissionRoleType AccessLevel { get; set; }
}

public class ApiResourcePropertyRoleDtoRead : IDtoRead
{
    public int Id { get; set; }
    public int ApiResourceId { get; set; }
    public string RoleName { get; set; } = default!;
    public DateTime Created { get; set; }
    public DateTime? Updated { get; set; }
    public List<ApiResourcePropertyRoleMappingDtoRead> Mappings { get; set; } = new();
}

public class ApiResourcePropertyRoleMappingDtoRead : IDtoRead
{
    public int Id { get; set; }
    public int ApiResourceRoleId { get; set; }
    public RoleMapType MappingType { get; set; }
    public string Value { get; set; } = default!;
    public string? Description { get; set; }
    public DateTime? Created { get; set; }
}

public class ApiResourcePropertySecretDtoRead : IDtoRead, IHasExpiration
{
    public int Id { get; set; }
    public int ApiResourceId { get; set; }
    public string? Description { get; set; }
    public DateTime? Expiration { get; set; }
    public string? Type { get; set; }
    public DateTime Created { get; set; }
    public string? Preview { get; set; }
}

public class ApiResourcePropertySecretValueDtoRead : ApiResourcePropertySecretDtoRead
{
    public string? Value { get; set; }
}

public class ApiResourcePropertyScopeDtoRead : IDtoRead
{
    public int Id { get; set; }
    public int ApiResourceId { get; set; }
    public required string Scope { get; set; }
    public DateTime? Created { get; set; }

    public ApiScopeDtoRead? ApiScope { get; set; }
}
