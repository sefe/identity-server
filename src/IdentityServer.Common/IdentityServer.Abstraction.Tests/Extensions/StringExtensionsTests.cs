using IdentityServer.Abstraction.Extensions;

namespace IdentityServer.Abstraction.Tests.Extensions;

[TestFixture]
public class StringExtensionsTests
{
    [Test]
    public void ReplaceJustOnce_ReplacesFirstOccurrence_Correctly()
    {
        // Arrange
        var input = "papa";
        var oldValue = "pa";
        var newValue = "ma";

        // Act
        var result = input.ReplaceJustOnce(oldValue, newValue);

        // Assert
        Assert.That(result, Is.EqualTo("mapa"));
    }

    [Test]
    public void ReplaceJustOnce_OldValueNotFound_ReturnsOriginal()
    {
        // Arrange
        var input = "hello world";
        var oldValue = "test";
        var newValue = "foo";

        // Act
        var result = input.ReplaceJustOnce(oldValue, newValue);

        // Assert
        Assert.That(result, Is.EqualTo(input));
    }

    [Test]
    public void ReplaceJustOnce_EmptyInput_ReturnsOriginal()
    {
        // Arrange
        var input = string.Empty;
        var oldValue = "a";
        var newValue = "b";

        // Act
        var result = input.ReplaceJustOnce(oldValue, newValue);

        // Assert
        Assert.That(result, Is.EqualTo(string.Empty));
    }

    [Test]
    public void ReplaceJustOnce_EmptyOldValue_ThrowsArgumentException()
    {
        // Arrange
        var input = "test";
        var oldValue = string.Empty;
        var newValue = "foo";

        // Act & Assert
        Assert.That(() => input.ReplaceJustOnce(oldValue, newValue), Throws.ArgumentException);
    }

    [Test]
    public void ReplaceJustOnce_EmptyNewValue_RemovesFirstOccurrence()
    {
        // Arrange
        var input = "banana";
        var oldValue = "na";
        var newValue = string.Empty;

        // Act
        var result = input.ReplaceJustOnce(oldValue, newValue);

        // Assert
        Assert.That(result, Is.EqualTo("bana"));
    }

    [Test]
    public void ReplaceJustOnce_MultipleOccurrences_OnlyFirstIsReplaced()
    {
        // Arrange
        var input = "test test test";
        var oldValue = "test";
        var newValue = "pass";
        var expected = "pass test test";

        // Act
        var result = input.ReplaceJustOnce(oldValue, newValue);

        // Assert
        Assert.That(result, Is.EqualTo(expected));
    }

    [Test]
    public void ReplaceJustOnce_OldValueAtStartAndEnd_OnlyFirstIsReplaced()
    {
        // Arrange
        var input = "abc123abc";
        var oldValue = "abc";
        var newValue = "xyz";

        // Act
        var result = input.ReplaceJustOnce(oldValue, newValue);

        // Assert
        Assert.That(result, Is.EqualTo("xyz123abc"));
    }
}
