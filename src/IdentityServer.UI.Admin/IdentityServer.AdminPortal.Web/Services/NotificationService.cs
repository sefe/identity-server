using Telerik.Blazor;
using Telerik.Blazor.Components;

namespace IdentityServer.AdminPortal.Web.Services;

public class NotificationService
{
    private TelerikNotification _notificationRef = default!;

    public void Init(TelerikNotification notificationRef)
    {
        _notificationRef = notificationRef ?? throw new ArgumentNullException(nameof(notificationRef));
    }

    public void ShowInfo(string message)
    {
        Show(message, ThemeConstants.Notification.ThemeColor.Dark);
    }

    private void Show(string message, string themeColor = "primary")
    {
        _notificationRef?.Show(new NotificationModel
        {
            Text = message,
            ThemeColor = themeColor,
            CloseAfter = 4000
        });
    }
}
