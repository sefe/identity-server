using Duende.IdentityServer.EntityFramework.Entities;
using IdentityServer.Abstraction.Contracts;
using IdentityServer.Abstraction.Entities.IdentityServerConfig.SystemPermissions;
using IdentityServer.Data.Entities.Roles;

namespace IdentityServer.Data.DuendeEntityExtensions;

public class ClientExt : Client, IPermissionBasedEntity, IHasCreatedInfo, IHasUpdatedInfo, IHasPeriodData
{
    public ClientExt()
    {
        // Only set important defaults which differ from the base class

        // AlwaysIncludeUserClaimsInIdToken makes ID Token self-contained without UserInfo calls
        AlwaysIncludeUserClaimsInIdToken = true;

        // AllowPlainTextPkce disabled for security reasons
        AllowPlainTextPkce = false;

        // Refresh token settings as recommended by Duende
        RefreshTokenUsage = 0; //ReUse
        UpdateAccessTokenClaimsOnRefresh = true;
        RefreshTokenExpiration = 1; // Absolute token expiration

        // The only possible login method is external
        EnableLocalLogin = false;

        // AlwaysSendClientClaims let us return 'role' claim in M2M tokens without any prefix
        AlwaysSendClientClaims = true;
        ClientClaimsPrefix = null;
    }

    public int SystemPermissionEnvironmentId { get; set; }
    public required SystemPermissionEnvironment SystemPermissionEnvironment { get; set; }
    public string? CreatedBy { get; set; }
    public string? UpdatedBy { get; set; }
    
    // SQL Server temporal table period columns
    public DateTime ValidFrom { get; set; }
    public DateTime ValidTo { get; set; }
    
    public List<ClientRole> Roles { get; set; } = new(); // Navigation property for roles associated with the Client
    public List<ClientEntraApp> EntraApps { get; set; } = new(); // Navigation property for Entra AppIds associated with the Client

    DateTime? IHasCreatedInfo.Created
    {
        get => Created;
        set => Created = value ?? DateTime.UtcNow;
    }

    public override string ToString()
    {
        return $"Application '{Id}'";
    }
}
