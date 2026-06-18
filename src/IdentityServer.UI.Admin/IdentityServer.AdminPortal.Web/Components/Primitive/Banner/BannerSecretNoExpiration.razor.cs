using Microsoft.AspNetCore.Components;

namespace IdentityServer.AdminPortal.Web.Components.Primitive.Banner;

public partial class BannerSecretNoExpiration : BannerSecretBase
{
    protected override int GetFilteredSecretsCount()
    {
        return Secrets.Count(s => s.Expiration == null);
    }

    protected override MarkupString GetBannerMessage(int secretsCount)
    {
        return (MarkupString)$"<strong>Secrets Without Expiration:</strong> {secretsCount} {(secretsCount > 1 ? "secrets exist" : "secret exists")} without expiration and should be rotated.";
    }
}
