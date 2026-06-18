using System.Globalization;

namespace IdentityServer.AdminPortal.Web.Extensions;

public static class DateTimeExtensions
{
    public static string FormatForUi(this DateTime? date)
    {
        if (!date.HasValue)
        {
            return "N/A";
        }

        return $"{FormatUtcDate(date)} UTC ({GetTimeDifference(date)})";
    }

    public static string FormatUtcDate(this DateTime? date)
    {
        if (!date.HasValue)
        {
            return "N/A";
        }
        return date.Value.Kind == DateTimeKind.Utc
            ? date.Value.ToString(CultureInfo.CurrentCulture)
            : DateTime.SpecifyKind(date.Value, DateTimeKind.Utc).ToString(CultureInfo.CurrentCulture);
    }

    public static string GetTimeDifference(this DateTime? date)
    {
        if (!date.HasValue)
        {
            return "N/A";
        }

        var now = DateTime.UtcNow;
        var difference = now - date.Value;

        if (difference.TotalSeconds < 1)
        {
            return "just now";
        }

        if (difference.TotalSeconds < 60)
        {
            return $"{(int)difference.TotalSeconds} sec ago";
        }

        if (difference.TotalMinutes < 60)
        {
            return $"{(int)difference.TotalMinutes} min ago";
        }

        if (difference.TotalHours < 24)
        {
            return $"{(int)difference.TotalHours} hour{(difference.TotalHours >= 2 ? "s" : "")} ago";
        }

        if (difference.TotalDays < 30)
        {
            return $"{(int)difference.TotalDays} day{(difference.TotalDays >= 2 ? "s" : "")} ago";
        }

        if (difference.TotalDays < 365)
        {
            return $"{(int)(difference.TotalDays / 30)} month{(difference.TotalDays / 30 >= 2 ? "s" : "")} ago";
        }

        return $"{(int)(difference.TotalDays / 365)} year{(difference.TotalDays / 365 >= 2 ? "s" : "")} ago";
    }
}
