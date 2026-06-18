using Microsoft.AspNetCore.Components;
using Telerik.SvgIcons;
using IdentityServer.Abstraction.Contracts;

namespace IdentityServer.AdminPortal.Web.Components.Primitive.Banner;

public abstract partial class BannerSecretBase : ComponentBase
{
    [Parameter]
    public IEnumerable<IHasExpiration> Secrets { get; set; } = new List<IHasExpiration>();

    protected bool IsDismissed { get; set; }

    protected virtual string AlertCssClass => "alert-warning";

    protected virtual ISvgIcon IconType => SvgIcon.ExclamationCircle;

    protected abstract int GetFilteredSecretsCount();

    protected abstract MarkupString GetBannerMessage(int secretsCount);

    protected async Task Dismiss()
    {
        IsDismissed = true;
    }
}
