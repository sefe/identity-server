// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

namespace IdentityServer.Abstraction.Extensions;

public static class DateTimeExtensions
{
    public static bool IsExpired(this DateTime? expiration)
    {
        return expiration.HasValue && expiration.Value < DateTime.UtcNow;
    }

    public static bool IsExpiringSoon(this DateTime? expiration, int daysBeforeExpiration)
    {
        return expiration.HasValue && !IsExpired(expiration) && expiration.Value < DateTime.UtcNow.AddDays(daysBeforeExpiration);
    }

    public static int? GetTimeDistanceInDays(this DateTime? expiration)
    {
        if (!expiration.HasValue)
        {
            return null;
        }
        return GetTimeDistanceInDays(expiration.Value);
    }

    public static int GetTimeDistanceInDays(this DateTime expiration)
    {
        var days = (int)Math.Clamp((expiration - DateTime.UtcNow).TotalDays, int.MinValue, int.MaxValue);

        return Math.Abs(days);
    }

    public static string FormatAsUtcString(this DateTime? dateTime)
    {
        if (!dateTime.HasValue)
        {
            return string.Empty;
        }
        return FormatAsUtcString(dateTime.Value);
    }

    public static string FormatAsUtcString(this DateTime dateTime)
    {
        return dateTime.ToUniversalTime().ToString("yyyy-MM-dd HH:mm 'UTC'");
    }

    public static string GetExpirationCssClass(this DateTime? expiration, int daysBeforeExpiration)
    {
        if (expiration.IsExpired())
        {
            return "text-danger fw-bold";
        }

        if (expiration == null || expiration.IsExpiringSoon(daysBeforeExpiration))
        {
            return "text-warning fw-bold";
        }

        return string.Empty;
    }
}
