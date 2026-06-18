using IdentityServer.Abstraction.Contracts;
using IdentityServer.Abstraction.Entities.IdentityServerConfig;
using IdentityServer.Abstraction.Entities.IdentityServerConfig.SystemPermissions;

namespace IdentityServer.Abstraction.DTO.Clients;

public class ClientDtoRead : IDtoRead, IHasEnvironment
{
    public int Id { get; set; }
    public required string ClientId { get; set; }
    public required string ClientName { get; set; }
    public string? Description { get; set; }
    public bool Enabled { get; set; }
    public bool RequirePkce { get; set; }
    public bool RequireClientSecret { get; set; }
    public ClientAccessTokenType AccessTokenType { get; set; }
    public bool AllowOfflineAccess { get; set; }
    public int SystemPermissionId { get; set; }
    public string SystemPermissionName { get; set; } = string.Empty;
    public int SystemPermissionEnvironmentId { get; set; }
    public string SystemPermissionEnvironmentName { get; set; } = string.Empty;
    public SystemPermissionRoleType AccessLevel { get; set; }
    public List<ClientPropertyGrantDtoRead> AllowedGrantTypes { get; set; } = new();
    public List<ClientPropertyRedirectUriDtoRead> RedirectUris { get; set; } = new();
    public List<ClientPropertyPostLogoutRedirectUriDtoRead> PostLogoutRedirectUris { get; set; } = new();
    public List<ClientPropertyCorsOriginDtoRead> AllowedCorsOrigins { get; set; } = new();
    public List<ClientPropertySecretDtoRead> ClientSecrets { get; set; } = new();
    public List<ClientPropertyScopeDtoRead> AllowedScopes { get; set; } = new();
    public List<ClientPropertyRoleDtoRead> Roles { get; set; } = new();
    public List<ClientPropertyEntraAppDtoRead> EntraApps { get; set; } = new();
    public DateTime Created { get; set; }
    public DateTime? Updated { get; set; }
    public string? UpdateReason { get; set; }
}

public class ClientPropertyGrantDtoRead : IDtoRead
{
    public int Id { get; set; }
    public int ClientId { get; set; }
    public required string GrantType { get; set; }
    public DateTime? Created { get; set; }
}

public class ClientPropertyEntraAppDtoRead : IDtoRead
{
    public int Id { get; set; }
    public int ClientId { get; set; }
    public required string AppId { get; set; }
    public required string AppName { get; set; }
    public DateTime Created { get; set; }
    public string? CreatedBy { get; set; }
}

public class ClientPropertyRedirectUriDtoRead : IDtoRead
{
    public int Id { get; set; }
    public int ClientId { get; set; }
    public required string RedirectUri { get; set; }
    public DateTime? Created { get; set; }
}

public class ClientPropertyPostLogoutRedirectUriDtoRead : IDtoRead
{
    public int Id { get; set; }
    public int ClientId { get; set; }
    public required string PostLogoutRedirectUri { get; set; }
    public DateTime? Created { get; set; }
}

public class ClientPropertyCorsOriginDtoRead : IDtoRead
{
    public int Id { get; set; }
    public int ClientId { get; set; }
    public required string Origin { get; set; }
    public DateTime? Created { get; set; }
}

public class ClientPropertyRoleDtoRead : IDtoRead
{
    public int Id { get; set; }
    public int ClientId { get; set; }
    public string RoleName { get; set; } = default!;
    public DateTime Created { get; set; }
    public DateTime? Updated { get; set; }
    public List<ClientPropertyRoleMappingDtoRead> Mappings { get; set; } = new();
}

public class ClientPropertyRoleMappingDtoRead : IDtoRead
{
    public int Id { get; set; }
    public int ClientRoleId { get; set; }
    public ClientRoleMapType MappingType { get; set; }
    public string Value { get; set; } = default!;
    public string? Description { get; set; }
    public DateTime? Created { get; set; }
}

public class ClientPropertySecretDtoRead : IDtoRead, IHasExpiration
{
    public int Id { get; set; }
    public int ClientId { get; set; }
    public string? Description { get; set; }
    public DateTime? Expiration { get; set; }
    public string? Type { get; set; }
    public DateTime Created { get; set; }
    public string? Preview { get; set; }
}

public class ClientPropertySecretValueDtoRead : ClientPropertySecretDtoRead
{
    public string? Value { get; set; }
}

public class ClientPropertyScopeDtoRead : IDtoRead
{
    public int Id { get; set; }
    public int ClientId { get; set; }
    public required string Scope { get; set; }
    public bool ApiResourceEnabled { get; set; } = true;
    public DateTime? Created { get; set; }

    public ApiScopeDtoRead? ApiScope { get; set; }
}
