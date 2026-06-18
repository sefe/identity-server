
namespace IdentityServer.AdminPortal.Web.Services;

public interface IConfirmationService
{
    event Func<string, string, string, bool, Task>? OnShow;

    Task<bool> ConfirmAsync(string title, string message, bool confirmCancel = true);
    Task<bool> ConfirmAsync(string title, string message, string link, bool confirmCancel = true);
    Task<bool> ConfirmLeavingDirtyPageAsync();
    void SetConfirmationResult(bool confirmed);
}