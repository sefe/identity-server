// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

using IdentityServer.Abstraction.Enums;

namespace IdentityServer.AdminPortal.Web.Extensions;

public static class HistoryEventTypeExtensions
{
    public static string GetBadgeColor(this HistoryEventType? eventType) => eventType switch
    {
        HistoryEventType.Created => "success",
        HistoryEventType.Updated => "primary",
        HistoryEventType.Deleted => "danger",
        _ => "secondary"
    };

    public static string GetBadgeColor(this HistoryEventType eventType) => GetBadgeColor((HistoryEventType?)eventType);
}
