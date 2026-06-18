using Microsoft.AspNetCore.Components;

namespace IdentityServer.AdminPortal.Web.Components.Primitive.ClientGrant;

public class ClientGrantItemListItem
{
    public string Text { get; set; } = string.Empty;
    public EventCallback OnClick { get; set; }
    public string? Tooltip { get; set; }
    public bool IsReadonly { get; set; } = false;
}
