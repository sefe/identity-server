// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

using System.ComponentModel.DataAnnotations;
using IdentityServer.Abstraction.Entities.IdentityServerConfig;
using IdentityServer.Abstraction.Entities.Validation;

namespace IdentityServer.Abstraction.Tests.Entities.Validation;

[TestFixture]
public class ClientGrantTypeValidationAttributeTests
{
    private ClientGrantTypeValidationAttribute _attribute;
    private ValidationContext _context;

    [SetUp]
    public void SetUp()
    {
        _attribute = new ClientGrantTypeValidationAttribute();
        _context = new ValidationContext(new object(), null, null)
        {
            MemberName = "GrantTypes"
        };
    }

    [TestCaseSource(nameof(GetAllowedGrantTypes))]
    public void IsValid_WithValidSingleGrantType_ReturnsSuccess(string grantType)
    {
        // Act
        var result = _attribute.GetValidationResult(grantType, _context);

        // Assert
        Assert.That(result, Is.EqualTo(ValidationResult.Success));
    }

    [Test]
    public void IsValid_WithInvalidSingleGrantType_ReturnsError()
    {
        // Arrange
        var invalidGrantType = "invalid_grant_type";

        // Act
        var result = _attribute.GetValidationResult(invalidGrantType, _context);

        // Assert
        Assert.That(result, Is.Not.Null);
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result!.ErrorMessage, Does.Contain(invalidGrantType));
            Assert.That(result.MemberNames, Contains.Item("GrantTypes"));
        }
    }

    [Test]
    public void IsValid_WithValidGrantTypeCollection_ReturnsSuccess()
    {
        // Arrange
        var validGrantTypes = new HashSet<string>(ClientGrantTypeNames.AllowedGrantsIds);

        // Act
        var result = _attribute.GetValidationResult(validGrantTypes, _context);

        // Assert
        Assert.That(result, Is.EqualTo(ValidationResult.Success));
    }

    [Test]
    public void IsValid_WithValidGrantTypeEnumerable_ReturnsSuccess()
    {
        // Arrange
        var validGrantTypes = GetGrantTypes();

        // Act
        var result = _attribute.GetValidationResult(validGrantTypes, _context);

        // Assert
        Assert.That(result, Is.EqualTo(ValidationResult.Success));

        static IEnumerable<string> GetGrantTypes()
        {

            yield return ClientGrantTypeNames.Grant_ClientCredentials;
            yield return ClientGrantTypeNames.Grant_TokenExchange;

        }
    }

    [Test]
    public void IsValid_WithInvalidGrantTypeInCollection_ReturnsError()
    {
        // Arrange
        var invalidGrantType = "invalid_grant_type";
        var grantTypes = new List<string> { ClientGrantTypeNames.Grant_ClientCredentials, invalidGrantType };

        // Act
        var result = _attribute.GetValidationResult(grantTypes, _context);

        // Assert
        Assert.That(result, Is.Not.Null);
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result!.ErrorMessage, Does.Contain(invalidGrantType));
            Assert.That(result.MemberNames, Contains.Item("GrantTypes"));
        }
    }

    [Test]
    public void IsValid_WithEmptyCollection_ReturnsSuccess()
    {
        // Arrange
        var grantTypes = new HashSet<string>();

        // Act
        var result = _attribute.GetValidationResult(grantTypes, _context);

        // Assert
        Assert.That(result, Is.EqualTo(ValidationResult.Success));
    }

    [Test]
    public void IsValid_WithNullValue_ReturnsSuccess()
    {
        // Act
        var result = _attribute.GetValidationResult(null, _context);

        // Assert
        Assert.That(result, Is.EqualTo(ValidationResult.Success));
    }

    [TestCaseSource(nameof(GetDisallowedGrantTypes))]
    public void IsValid_WithDisallowedGrantType_ReturnsError(string disallowedGrantType)
    {
        // Act
        var result = _attribute.GetValidationResult(disallowedGrantType, _context);

        // Assert
        Assert.That(result, Is.Not.Null);
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result!.ErrorMessage, Does.Contain(disallowedGrantType));
            Assert.That(result.MemberNames, Contains.Item("GrantTypes"));
        }
    }

    private static IEnumerable<TestCaseData> GetAllowedGrantTypes()
    {
        foreach (var grantType in ClientGrantTypeNames.AllowedGrantsIds)
        {
            yield return new TestCaseData(grantType);
        }
    }

    private static IEnumerable<TestCaseData> GetDisallowedGrantTypes()
    {
        var disallowedGrants = ClientGrantTypeNames.AllGrantTypes.Keys
            .Except(ClientGrantTypeNames.AllowedGrantsIds)
            .ToList();

        foreach (var grantType in disallowedGrants)
        {
            yield return new TestCaseData(grantType);
        }
    }
}
