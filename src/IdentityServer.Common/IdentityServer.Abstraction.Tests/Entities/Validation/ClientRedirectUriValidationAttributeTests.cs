// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

using System.ComponentModel.DataAnnotations;
using IdentityServer.Abstraction.Entities.Validation;

namespace IdentityServer.Abstraction.Tests.Entities.Validation;

[TestFixture]
public class ClientRedirectUriValidationAttributeTests
{
    private ClientRedirectUriValidationAttribute _attribute;

    [SetUp]
    public void SetUp()
    {
        _attribute = new ClientRedirectUriValidationAttribute();
    }

    [TestCase("https://example.com/callback")]
    [TestCase("http://localhost:5000/callback")]
    [TestCase("http://127.0.0.1:5000/callback")]
    public void IsValid_WithValidRedirectUri_ReturnsSuccess(string value)
    {
        // Arrange
        var context = new ValidationContext(new object(), null, null) { MemberName = "RedirectUri" };

        // Act
        var result = _attribute.GetValidationResult(value, context);

        // Assert
        Assert.That(result, Is.EqualTo(ValidationResult.Success));
    }

    [TestCase(null, "Redirect URI cannot be null or empty.")]
    [TestCase("", "Redirect URI cannot be null or empty.")]
    [TestCase("   ", "Redirect URI cannot be null or empty.")]
    [TestCase("https://example.com/*", "Redirect URI cannot contain wildcards.")]
    [TestCase("https://*.example.com/callback", "Redirect URI cannot contain wildcards.")]
    [TestCase("/callback", "Redirect URI must be an absolute URI.")]
    [TestCase("/", "Redirect URI must be an absolute URI.")]
    [TestCase("http://exa mple.com", "Redirect URI must be an absolute URI.")]
    public void IsValid_WithInvalidRedirectUri_ReturnsError(string? value, string expectedError)
    {
        // Arrange
        var context = new ValidationContext(new object(), null, null) { MemberName = "RedirectUri" };

        // Act
        var result = _attribute.GetValidationResult(value, context);

        // Assert
        Assert.That(result, Is.Not.Null);
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result.ErrorMessage, Is.EqualTo(expectedError));
            Assert.That(result.MemberNames, Contains.Item("RedirectUri"));
        }
    }
}
