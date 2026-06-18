using IdentityServer.Abstraction.Extensions;

namespace IdentityServer.Abstraction.Tests.Extensions;

[TestFixture]
public class DateTimeExtensionsTests
{
    [Test]
    [TestCase(null, false)]
    [TestCase(-1, true)]
    [TestCase(1, false)]
    public void IsExpired_WithVariousInputs_ReturnsExpectedResult(int? daysDifference, bool expectedResult)
    {
        // Arrange
        DateTime? expiration = daysDifference.HasValue ? DateTime.UtcNow.AddDays(daysDifference.Value) : null;

        // Act
        var result = expiration.IsExpired();

        // Assert
        Assert.That(result, Is.EqualTo(expectedResult));
    }

    [Test]
    [TestCase(null, 7, false)]
    [TestCase(-1, 7, false)]
    [TestCase(5, 7, true)]
    [TestCase(10, 7, false)]
    public void IsExpiringSoon_WithVariousInputs_ReturnsExpectedResult(int? daysDifference, int daysBeforeExpiration, bool expectedResult)
    {
        // Arrange
        DateTime? expiration = daysDifference.HasValue ? DateTime.UtcNow.AddDays(daysDifference.Value) : null;

        // Act
        var result = expiration.IsExpiringSoon(daysBeforeExpiration);

        // Assert
        Assert.That(result, Is.EqualTo(expectedResult));
    }

    [Test]
    public void GetTimeDistanceInDays_WithNullExpiration_ReturnsNull()
    {
        // Arrange
        DateTime? expiration = null;

        // Act
        var result = expiration.GetTimeDistanceInDays();

        // Assert
        Assert.That(result, Is.Null);
    }

    [Test]
    public void GetTimeDistanceInDays_WithFutureDate_ReturnsPositiveDays()
    {
        // Arrange
        DateTime? expiration = DateTime.UtcNow.AddDays(10);

        // Act
        var result = expiration.GetTimeDistanceInDays();

        // Assert
        Assert.That(result, Is.InRange(9, 10));
    }

    [Test]
    public void GetTimeDistanceInDays_WithPastDate_ReturnsPositiveDays()
    {
        // Arrange
        DateTime? expiration = DateTime.UtcNow.AddDays(-10);

        // Act
        var result = expiration.GetTimeDistanceInDays();

        // Assert
        Assert.That(result, Is.EqualTo(10));
    }

    [Test]
    public void GetTimeDistanceInDays_WithNonNullableDateTime_ReturnsAbsoluteDays()
    {
        // Arrange
        DateTime expiration = DateTime.UtcNow.AddDays(-15);

        // Act
        var result = expiration.GetTimeDistanceInDays();

        // Assert
        Assert.That(result, Is.EqualTo(15));
    }

    [Test]
    public void GetTimeDistanceInDays_WithNonNullableFutureDateTime_ReturnsAbsoluteDays()
    {
        // Arrange
        DateTime expiration = DateTime.UtcNow.AddDays(20);

        // Act
        var result = expiration.GetTimeDistanceInDays();

        // Assert
        Assert.That(result, Is.InRange(19, 20));
    }

    [Test]
    public void FormatAsUtcString_WithNullDateTime_ReturnsEmptyString()
    {
        // Arrange
        DateTime? dateTime = null;

        // Act
        var result = dateTime.FormatAsUtcString();

        // Assert
        Assert.That(result, Is.EqualTo(string.Empty));
    }

    [Test]
    public void FormatAsUtcString_WithValidDateTime_ReturnsFormattedString()
    {
        // Arrange
        DateTime? dateTime = new DateTime(2024, 1, 15, 14, 30, 0, DateTimeKind.Utc);

        // Act
        var result = dateTime.FormatAsUtcString();

        // Assert
        Assert.That(result, Is.EqualTo("2024-01-15 14:30 UTC"));
    }

    [Test]
    public void FormatAsUtcString_WithNonNullableDateTime_ReturnsFormattedString()
    {
        // Arrange
        DateTime dateTime = new DateTime(2024, 12, 25, 23, 59, 59, DateTimeKind.Utc);

        // Act
        var result = dateTime.FormatAsUtcString();

        // Assert
        Assert.That(result, Is.EqualTo("2024-12-25 23:59 UTC"));
    }

    [Test]
    public void FormatAsUtcString_WithLocalDateTime_ConvertsToUtc()
    {
        // Arrange
        DateTime localDateTime = new DateTime(2024, 6, 15, 12, 0, 0, DateTimeKind.Local);
        DateTime utcEquivalent = localDateTime.ToUniversalTime();
        string expectedFormat = utcEquivalent.ToString("yyyy-MM-dd HH:mm 'UTC'");

        // Act
        var result = localDateTime.FormatAsUtcString();

        // Assert
        Assert.That(result, Is.EqualTo(expectedFormat));
    }

    [Test]
    public void GetExpirationCssClass_WithExpiredDate_ReturnsDangerClass()
    {
        // Arrange
        DateTime? expiration = DateTime.UtcNow.AddDays(-1);
        int daysBeforeExpiration = 7;

        // Act
        var result = expiration.GetExpirationCssClass(daysBeforeExpiration);

        // Assert
        Assert.That(result, Is.EqualTo("text-danger fw-bold"));
    }

    [Test]
    public void GetExpirationCssClass_WithNullExpiration_ReturnsWarningClass()
    {
        // Arrange
        DateTime? expiration = null;
        int daysBeforeExpiration = 7;

        // Act
        var result = expiration.GetExpirationCssClass(daysBeforeExpiration);

        // Assert
        Assert.That(result, Is.EqualTo("text-warning fw-bold"));
    }

    [Test]
    public void GetExpirationCssClass_WithExpiringSoonDate_ReturnsWarningClass()
    {
        // Arrange
        DateTime? expiration = DateTime.UtcNow.AddDays(5);
        int daysBeforeExpiration = 7;

        // Act
        var result = expiration.GetExpirationCssClass(daysBeforeExpiration);

        // Assert
        Assert.That(result, Is.EqualTo("text-warning fw-bold"));
    }

    [Test]
    public void GetExpirationCssClass_WithValidFutureDate_ReturnsEmptyString()
    {
        // Arrange
        DateTime? expiration = DateTime.UtcNow.AddDays(30);
        int daysBeforeExpiration = 7;

        // Act
        var result = expiration.GetExpirationCssClass(daysBeforeExpiration);

        // Assert
        Assert.That(result, Is.EqualTo(string.Empty));
    }

    [Test]
    public void GetExpirationCssClass_WithDateAtThreshold_ReturnsEmptyString()
    {
        // Arrange
        DateTime? expiration = DateTime.UtcNow.AddDays(7).AddSeconds(1);
        int daysBeforeExpiration = 7;

        // Act
        var result = expiration.GetExpirationCssClass(daysBeforeExpiration);

        // Assert
        Assert.That(result, Is.EqualTo(string.Empty));
    }
}
