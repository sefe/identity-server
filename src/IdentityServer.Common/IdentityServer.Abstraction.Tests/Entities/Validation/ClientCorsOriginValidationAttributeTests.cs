// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

using System.ComponentModel.DataAnnotations;
using IdentityServer.Abstraction.Entities.Validation;

namespace IdentityServer.Abstraction.Tests.Entities.Validation;

[TestFixture]
public class ClientCorsOriginValidationAttributeTests
{
    private ClientCorsOriginValidationAttribute _attribute;

    [SetUp]
    public void SetUp()
    {
        _attribute = new ClientCorsOriginValidationAttribute();
    }

    [TestCase("https://example.com")]
    [TestCase("http://example.com:8888")]
    public void IsValid_WithValidOrigin_ReturnsSuccess(string value)
    {
        // Arrange
        //object? value = ;
        var context = new ValidationContext(new object(), null, null) { MemberName = "Origin" };

        // Act
        var result = _attribute.GetValidationResult(value, context);

        // Assert
        Assert.That(result, Is.EqualTo(ValidationResult.Success));
    }

    [TestCase(null, "CORS origin must not be empty.")]
    [TestCase("", "CORS origin must not be empty.")]
    [TestCase("*", "Wildcard CORS origin is not allowed.")]
    [TestCase("https://example.com/", "CORS origin must end with hostname or port number.")]
    [TestCase("example.com", "CORS origin must start with 'http://' or 'https://'.")]
    [TestCase("http://exa mple.com", "Failed to validate CORS origin.")]
    [TestCase("http://example.com:*", "Failed to validate CORS origin.")]
    [TestCase("http://*.com", "Failed to validate CORS origin.")]
    [TestCase("https://example.com/path", "CORS origins shouldn't have paths.")]
    [TestCase("https://example.com?foo=bar", "CORS origins shouldn't have query strings.")]
    [TestCase("https://example.com#fragment", "CORS origins shouldn't have fragments.")]
    public void IsValid_WithInvalidValue_ReturnsError(string? value, string expectedError)
    {
        // Arrange
        var context = new ValidationContext(new object(), null, null) { MemberName = "Origin" };

        // Act
        var result = _attribute.GetValidationResult(value, context);

        // Assert
        Assert.That(result, Is.Not.Null);
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result.ErrorMessage, Is.EqualTo(expectedError));
            Assert.That(result.MemberNames, Contains.Item("Origin"));
        }
    }
}
