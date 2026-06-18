namespace IdentityServer.AdminPortal.Web.Components.Interop;

public interface IClipboardService
{
    Task CopyToClipboard(string text);
}
