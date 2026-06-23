// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

using Bunit;
using IdentityServer.AdminPortal.Web.Components.Primitive;
using TestContext = Bunit.TestContext;

namespace IdentityServer.AdminPortal.Web.Tests.Components.Primitive;

[TestFixture]
public class SecretExpirationDisplayTests : TestContext
{
    [Test]
    public void Render_WithNullExpiration_ShowsNeverExpiresBadge()
    {
        // Arrange
        const int daysBeforeNotification = 60;

        // Act
        var cut = RenderComponent<SecretExpirationDisplay>(parameters => parameters
            .Add(p => p.Expiration, null)
            .Add(p => p.DaysBeforeExpirationNotification, daysBeforeNotification));

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(cut.Markup, Does.Contain("Never expires"));
            var badge = cut.Find("span.badge.bg-warning");
            Assert.That(badge.TextContent, Is.EqualTo("Never expires"));
        }
    }

    [Test]
    public void Render_WithNullExpiration_ShowsEmptyDateString()
    {
        // Arrange
        const int daysBeforeNotification = 60;

        // Act
        var cut = RenderComponent<SecretExpirationDisplay>(parameters => parameters
            .Add(p => p.Expiration, null)
            .Add(p => p.DaysBeforeExpirationNotification, daysBeforeNotification));

        // Assert
        // FormatAsUtcString returns empty string for null DateTime
        Assert.That(cut.Markup, Does.Not.Contain("UTC"));
    }

    [Test]
    public void Render_WithExpiredDate_ShowsExpiredBadge()
    {
        // Arrange
        var expiredDate = DateTime.UtcNow.AddDays(-30);
        const int daysBeforeNotification = 60;

        // Act
        var cut = RenderComponent<SecretExpirationDisplay>(parameters => parameters
            .Add(p => p.Expiration, expiredDate)
            .Add(p => p.DaysBeforeExpirationNotification, daysBeforeNotification));

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(cut.Markup, Does.Contain("Expired"));
            Assert.That(cut.Markup, Does.Contain("days ago"));
            var badge = cut.Find("span.badge.bg-danger");
            Assert.That(badge.TextContent, Does.Contain("Expired"));
            Assert.That(badge.TextContent, Does.Contain("30"));
        }
    }

    [Test]
    public void Render_WithExpiredDate_ShowsFormattedUtcDate()
    {
        // Arrange
        var expiredDate = new DateTime(2024, 1, 15, 10, 30, 0, DateTimeKind.Utc);
        const int daysBeforeNotification = 60;

        // Act
        var cut = RenderComponent<SecretExpirationDisplay>(parameters => parameters
            .Add(p => p.Expiration, expiredDate)
            .Add(p => p.DaysBeforeExpirationNotification, daysBeforeNotification));

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(cut.Markup, Does.Contain("2024-01-15"));
            Assert.That(cut.Markup, Does.Contain("10:30"));
            Assert.That(cut.Markup, Does.Contain("UTC"));
        }
    }

    [Test]
    public void Render_WithDateExpiringSoon_ShowsExpiringSoonBadge()
    {
        // Arrange
        var expiringDate = DateTime.UtcNow.AddDays(30);
        const int daysBeforeNotification = 60;

        // Act
        var cut = RenderComponent<SecretExpirationDisplay>(parameters => parameters
            .Add(p => p.Expiration, expiringDate)
            .Add(p => p.DaysBeforeExpirationNotification, daysBeforeNotification));

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(cut.Markup, Does.Contain("Expires in"));
            Assert.That(cut.Markup, Does.Contain("days"));
            var badge = cut.Find("span.badge.bg-warning");
            Assert.That(badge.TextContent, Does.Contain("Expires in"));
            // Days calculation may be 29 or 30 due to rounding
            Assert.That(badge.TextContent, Does.Match(@"Expires in (29|30) days"));
        }
    }

    [Test]
    public void Render_WithDateNotExpiringSoon_ShowsOnlyFormattedDate()
    {
        // Arrange
        var futureDate = DateTime.UtcNow.AddDays(90);
        const int daysBeforeNotification = 60;

        // Act
        var cut = RenderComponent<SecretExpirationDisplay>(parameters => parameters
            .Add(p => p.Expiration, futureDate)
            .Add(p => p.DaysBeforeExpirationNotification, daysBeforeNotification));

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(cut.Markup, Does.Contain("UTC"));
            Assert.That(cut.Markup, Does.Not.Contain("Expires in"));
            Assert.That(cut.Markup, Does.Not.Contain("Expired"));
            Assert.That(cut.Markup, Does.Not.Contain("Never expires"));
            var badges = cut.FindAll("span.badge");
            Assert.That(badges, Is.Empty);
        }
    }

    [Test]
    public void Render_WithExpirationOnBoundary_ShowsExpiringSoonBadge()
    {
        // Arrange
        const int daysBeforeNotification = 60;
        var boundaryDate = DateTime.UtcNow.AddDays(daysBeforeNotification - 1);

        // Act
        var cut = RenderComponent<SecretExpirationDisplay>(parameters => parameters
            .Add(p => p.Expiration, boundaryDate)
            .Add(p => p.DaysBeforeExpirationNotification, daysBeforeNotification));

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(cut.Markup, Does.Contain("Expires in"));
            var badge = cut.Find("span.badge.bg-warning");
            Assert.That(badge, Is.Not.Null);
        }
    }

    [Test]
    public void Render_WithExpirationJustPastBoundary_ShowsOnlyFormattedDate()
    {
        // Arrange
        const int daysBeforeNotification = 60;
        var justPastBoundaryDate = DateTime.UtcNow.AddDays(daysBeforeNotification + 1);

        // Act
        var cut = RenderComponent<SecretExpirationDisplay>(parameters => parameters
            .Add(p => p.Expiration, justPastBoundaryDate)
            .Add(p => p.DaysBeforeExpirationNotification, daysBeforeNotification));

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(cut.Markup, Does.Not.Contain("Expires in"));
            var badges = cut.FindAll("span.badge");
            Assert.That(badges, Is.Empty);
        }
    }

    [Test]
    public void Render_WithExpiredDateYesterday_ShowsOneDay()
    {
        // Arrange
        var yesterday = DateTime.UtcNow.AddDays(-1);
        const int daysBeforeNotification = 60;

        // Act
        var cut = RenderComponent<SecretExpirationDisplay>(parameters => parameters
            .Add(p => p.Expiration, yesterday)
            .Add(p => p.DaysBeforeExpirationNotification, daysBeforeNotification));

        // Assert
        using (Assert.EnterMultipleScope())
        {
            var badge = cut.Find("span.badge.bg-danger");
            Assert.That(badge.TextContent, Does.Contain("Expired"));
            Assert.That(badge.TextContent, Does.Contain("1"));
            Assert.That(badge.TextContent, Does.Contain("days ago"));
        }
    }

    [Test]
    public void Render_WithExpirationTomorrow_ShowsOneDay()
    {
        // Arrange
        var tomorrow = DateTime.UtcNow.AddDays(1);
        const int daysBeforeNotification = 60;

        // Act
        var cut = RenderComponent<SecretExpirationDisplay>(parameters => parameters
            .Add(p => p.Expiration, tomorrow)
            .Add(p => p.DaysBeforeExpirationNotification, daysBeforeNotification));

        // Assert
        using (Assert.EnterMultipleScope())
        {
            var badge = cut.Find("span.badge.bg-warning");
            Assert.That(badge.TextContent, Does.Contain("Expires in"));
            // Days calculation may be 0 or 1 due to rounding of partial days
            Assert.That(badge.TextContent, Does.Match(@"Expires in [01] days"));
        }
    }

    [Test]
    public void Render_WithDifferentNotificationThresholds_RespectsThreshold()
    {
        // Arrange
        var expirationDate = DateTime.UtcNow.AddDays(45);
        const int shortThreshold = 30;
        const int longThreshold = 60;

        // Act
        var cutShortThreshold = RenderComponent<SecretExpirationDisplay>(parameters => parameters
            .Add(p => p.Expiration, expirationDate)
            .Add(p => p.DaysBeforeExpirationNotification, shortThreshold));

        var cutLongThreshold = RenderComponent<SecretExpirationDisplay>(parameters => parameters
            .Add(p => p.Expiration, expirationDate)
            .Add(p => p.DaysBeforeExpirationNotification, longThreshold));

        // Assert
        using (Assert.EnterMultipleScope())
        {
            // With 30-day threshold, 45 days away should not show warning
            var shortThresholdBadges = cutShortThreshold.FindAll("span.badge");
            Assert.That(shortThresholdBadges, Is.Empty, "Should not show badge with 30-day threshold");

            // With 60-day threshold, 45 days away should show warning
            var longThresholdBadge = cutLongThreshold.Find("span.badge.bg-warning");
            Assert.That(longThresholdBadge.TextContent, Does.Contain("Expires in"));
        }
    }

    [Test]
    public void Render_WithLocalDateTime_ConvertsToUtc()
    {
        // Arrange
        var localDate = new DateTime(2024, 6, 15, 14, 30, 0, DateTimeKind.Local);
        const int daysBeforeNotification = 60;

        // Act
        var cut = RenderComponent<SecretExpirationDisplay>(parameters => parameters
            .Add(p => p.Expiration, localDate)
            .Add(p => p.DaysBeforeExpirationNotification, daysBeforeNotification));

        // Assert
        // FormatAsUtcString converts to UTC
        Assert.That(cut.Markup, Does.Contain("UTC"));
    }

    [Test]
    public void Render_ExpirationToday_ShowsAsExpired()
    {
        // Arrange
        var today = DateTime.UtcNow.Date;
        const int daysBeforeNotification = 60;

        // Act
        var cut = RenderComponent<SecretExpirationDisplay>(parameters => parameters
            .Add(p => p.Expiration, today)
            .Add(p => p.DaysBeforeExpirationNotification, daysBeforeNotification));

        // Assert
        // If the time portion is before now, it's expired
        var badge = cut.Find("span.badge.bg-danger");
        Assert.That(badge.TextContent, Does.Contain("Expired"));
    }

    [Test]
    public void Component_HasCorrectBadgeClasses_ForAllStates()
    {
        // Arrange
        const int daysBeforeNotification = 60;

        // Act & Assert - Never expires
        var cutNeverExpires = RenderComponent<SecretExpirationDisplay>(parameters => parameters
            .Add(p => p.Expiration, null)
            .Add(p => p.DaysBeforeExpirationNotification, daysBeforeNotification));
        var neverExpiresBadge = cutNeverExpires.Find("span.badge.bg-warning");
        Assert.That(neverExpiresBadge, Is.Not.Null);

        // Act & Assert - Expired
        var cutExpired = RenderComponent<SecretExpirationDisplay>(parameters => parameters
            .Add(p => p.Expiration, DateTime.UtcNow.AddDays(-10))
            .Add(p => p.DaysBeforeExpirationNotification, daysBeforeNotification));
        var expiredBadge = cutExpired.Find("span.badge.bg-danger");
        Assert.That(expiredBadge, Is.Not.Null);

        // Act & Assert - Expiring soon
        var cutExpiringSoon = RenderComponent<SecretExpirationDisplay>(parameters => parameters
            .Add(p => p.Expiration, DateTime.UtcNow.AddDays(30))
            .Add(p => p.DaysBeforeExpirationNotification, daysBeforeNotification));
        var expiringSoonBadge = cutExpiringSoon.Find("span.badge.bg-warning");
        Assert.That(expiringSoonBadge, Is.Not.Null);
    }

    [Test]
    public void Render_BadgeHasLeftMargin()
    {
        // Arrange
        var expiredDate = DateTime.UtcNow.AddDays(-10);
        const int daysBeforeNotification = 60;

        // Act
        var cut = RenderComponent<SecretExpirationDisplay>(parameters => parameters
            .Add(p => p.Expiration, expiredDate)
            .Add(p => p.DaysBeforeExpirationNotification, daysBeforeNotification));

        // Assert
        var badge = cut.Find("span.badge");
        Assert.That(badge.ClassList, Does.Contain("ms-1"), "Badge should have left margin spacing");
    }
}
