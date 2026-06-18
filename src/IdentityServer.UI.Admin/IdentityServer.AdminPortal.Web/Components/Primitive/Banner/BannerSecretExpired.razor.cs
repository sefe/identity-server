using Microsoft.AspNetCore.Components;
using Telerik.SvgIcons;
using IdentityServer.Abstraction.Extensions;

namespace IdentityServer.AdminPortal.Web.Components.Primitive.Banner;

public partial class BannerSecretExpired : BannerSecretBase
{
    protected override string AlertCssClass => "alert-danger";

    protected override ISvgIcon IconType => SvgIcon.WarningTriangle;

    protected override int GetFilteredSecretsCount()
    {
        return Secrets.Count(s => s.Expiration.IsExpired());
    }

    protected override MarkupString GetBannerMessage(int secretsCount)
    {
        return (MarkupString)$"<strong>Secrets Expired:</strong> {secretsCount} {(secretsCount > 1 ? "secrets have" : "secret has")} expired.";
    }
}
