using IdentityServer.Abstraction.DTO.Clients;

namespace IdentityServer.AdminPortal.Web;

public static class ResourcesExtensions
{
    public static ClientDtoRead ShallowCopy(this ClientDtoRead source)
    {
        return new ClientDtoRead
        {
            Id = source.Id,
            ClientId = source.ClientId,
            ClientName = source.ClientName,
            Description = source.Description,
            Enabled = source.Enabled,
            RequirePkce = source.RequirePkce,
            RequireClientSecret = source.RequireClientSecret,
            AccessTokenType = source.AccessTokenType,
            AllowOfflineAccess = source.AllowOfflineAccess,
            SystemPermissionEnvironmentId = source.SystemPermissionEnvironmentId,
            AccessLevel = source.AccessLevel,
            AllowedGrantTypes = source.AllowedGrantTypes,
            RedirectUris = source.RedirectUris,
            PostLogoutRedirectUris = source.PostLogoutRedirectUris,
            AllowedCorsOrigins = source.AllowedCorsOrigins,
            ClientSecrets = source.ClientSecrets,
            AllowedScopes = source.AllowedScopes,
            Created = source.Created,
            Updated = source.Updated
        };
    }
}
