using System.ComponentModel.DataAnnotations;
using IdentityServer.Abstraction.Entities.Validation;

namespace IdentityServer.Abstraction.Tests.Entities.Validation;

[TestFixture]
public class TrimmedStringLengthAttributeTests
{
    private ValidationContext _validationContext;

    [SetUp]
    public void Setup()
    {
        _validationContext = new ValidationContext(new object(), null, null) { MemberName = "afield" };
    }

    [Test]
    public void IsValid_NullValue_ReturnsTrue()
    {
        // Arrange
        var attr = new TrimmedStringLengthAttribute { MinimumLength = 1, MaximumLength = 10 };

        // Act
        var result = attr.GetValidationResult(null, _validationContext);

        // Assert
        Assert.That(result, Is.EqualTo(ValidationResult.Success));
    }

    [Test]
    public void IsValid_StringLengthWithinBounds_ReturnsTrue()
    {
        // Arrange
        var attr = new TrimmedStringLengthAttribute { MinimumLength = 1, MaximumLength = 10 };

        // Act
        var result = attr.GetValidationResult("   abc   ", _validationContext);

        // Assert
        Assert.That(result, Is.EqualTo(ValidationResult.Success));
    }

    [Test]
    public void IsValid_StringLengthExactlyMaximum_ReturnsTrue()
    {
        // Arrange
        var attr = new TrimmedStringLengthAttribute { MinimumLength = 1, MaximumLength = 3 };

        // Act
        var result = attr.GetValidationResult("  abc  ", _validationContext);

        // Assert
        Assert.That(result, Is.EqualTo(ValidationResult.Success));
    }

    [Test]
    public void IsValid_EmptyStringWithinBounds_ReturnsTrue()
    {
        // Arrange
        var attr = new TrimmedStringLengthAttribute { MaximumLength = 3 }; // MinimumLength = 0 by default

        // Act
        var result = attr.GetValidationResult("", _validationContext);

        // Assert
        Assert.That(result, Is.EqualTo(ValidationResult.Success));
    }

    [Test]
    public void IsValid_StringLengthBelowMinimum_ReturnsFalse()
    {
        // Arrange
        var attr = new TrimmedStringLengthAttribute { MinimumLength = 4, MaximumLength = 10 };

        // Act
        var result = attr.GetValidationResult("   abc   ", _validationContext);

        // Assert
        Assert.That(result, Is.Not.Null);
        Assert.That(result.ErrorMessage, Is.Not.Null);
    }

    [Test]
    public void IsValid_StringLengthAboveMaximum_ReturnsFalse()
    {
        // Arrange
        var attr = new TrimmedStringLengthAttribute { MinimumLength = 1, MaximumLength = 3 };

        // Act
        var result = attr.GetValidationResult("abcd", _validationContext);

        // Assert
        Assert.That(result, Is.Not.Null);
        Assert.That(result.ErrorMessage, Is.Not.Null);
    }

    [Test]
    public void IsValid_NotString_ReturnsFalse()
    {
        // Arrange
        var attr = new TrimmedStringLengthAttribute { MinimumLength = 1, MaximumLength = 3 };

        // Act
        var result = attr.GetValidationResult(123.5, _validationContext);

        // Assert
        Assert.That(result, Is.Not.Null);
        Assert.That(result.ErrorMessage, Is.Not.Null);
    }
}
