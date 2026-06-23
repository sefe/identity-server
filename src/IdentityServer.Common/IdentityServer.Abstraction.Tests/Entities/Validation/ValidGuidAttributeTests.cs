// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

using System.ComponentModel.DataAnnotations;
using IdentityServer.Abstraction.Entities.Validation;

namespace IdentityServer.Abstraction.Tests.Entities.Validation;

[TestFixture]
public class ValidGuidAttributeTests
{
    private const string _validGuidString = "b3b6a6e2-7c2e-4b2a-9e2a-2e2b2c2d2e2f";
    private const string _emptyGuidString = "00000000-0000-0000-0000-000000000000";
    private const string _invalidGuidString = "not-a-guid";
    private const string _guidFormatN = "b3b6a6e27c2e4b2a9e2a2e2b2c2d2e2f"; // Format N: No hyphens
    private const string _guidFormatB = "{b3b6a6e2-7c2e-4b2a-9e2a-2e2b2c2d2e2f}"; // Format B: With braces
    private const string _guidFormatP = "(b3b6a6e2-7c2e-4b2a-9e2a-2e2b2c2d2e2f)"; // Format P: With parentheses
    private const string _guidFormatX = "{0xb3b6a6e2,0x7c2e,0x4b2a,{0x9e,0x2a,0x2e,0x2b,0x2c,0x2d,0x2e,0x2f}}"; // Format X: Hexadecimal
    private const string _expectedNonEmptyGuidMessage = "Value must be a valid non-empty GUID 'xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx'.";
    private const string _expectedTypeMessage = "Value is not of the expected type (string).";

    private ValidGuidAttribute _attribute = null!;

    [SetUp]
    public void SetUp()
    {
        _attribute = new ValidGuidAttribute();
    }

    [Test]
    public void IsValid_WithValidGuidString_ReturnsSuccess()
    {
        // Arrange
        var context = new ValidationContext(new object());

        // Act
        var result = _attribute.GetValidationResult(_validGuidString, context);

        // Assert
        Assert.That(result, Is.EqualTo(ValidationResult.Success));
    }

    [TestCase(_emptyGuidString)]
    [TestCase(_invalidGuidString)]
    [TestCase(_guidFormatN)]
    [TestCase(_guidFormatB)]
    [TestCase(_guidFormatP)]
    [TestCase(_guidFormatX)]
    public void IsValid_WithUnsupportedGuidFormat_ReturnsError(string invalidGuidValue)
    {
        // Arrange
        var context = new ValidationContext(new object());

        // Act
        var result = _attribute.GetValidationResult(invalidGuidValue, context);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result, Is.Not.Null);
            Assert.That(result!.ErrorMessage, Is.EqualTo(_expectedNonEmptyGuidMessage));
        }
    }

    [TestCase(null)]
    [TestCase(12345)]
    public void IsValid_WithNonStringValue_ReturnsError(object? invalidValue)
    {
        // Arrange
        var context = new ValidationContext(new object());

        // Act
        var result = _attribute.GetValidationResult(invalidValue, context);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result, Is.Not.Null);
            Assert.That(result!.ErrorMessage, Is.EqualTo(_expectedTypeMessage));
        }
    }
}
