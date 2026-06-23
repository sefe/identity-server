// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

using System.ComponentModel.DataAnnotations;
using IdentityServer.Abstraction.Entities.IdentityServerConfig;
using IdentityServer.Abstraction.Entities.Validation;

namespace IdentityServer.Abstraction.Tests.Entities.Validation;

[TestFixture]
public class ClientGrantTypeCompatibilityValidationAttributeTests
{
    private ClientGrantTypeCompatibilityValidationAttribute _attribute;
    private ValidationContext _context;

    [SetUp]
    public void SetUp()
    {
        _attribute = new ClientGrantTypeCompatibilityValidationAttribute();
        _context = new ValidationContext(new object(), null, null)
        {
            MemberName = "AllowedGrantTypes"
        };
    }

    [Test]
    public void IsValid_WithNoGrantTypes_ReturnsSuccess()
    {
        // Arrange
        var grantTypes = new List<string>();

        // Act
        var result = _attribute.GetValidationResult(grantTypes, _context);

        // Assert
        Assert.That(result, Is.EqualTo(ValidationResult.Success));
    }

    [Test]
    public void IsValid_WithSingleGrantType_ReturnsSuccess()
    {
        // Arrange
        var grantTypes = new List<string> { ClientGrantTypeNames.Grant_ClientCredentials };

        // Act
        var result = _attribute.GetValidationResult(grantTypes, _context);

        // Assert
        Assert.That(result, Is.EqualTo(ValidationResult.Success));
    }

    [TestCaseSource(nameof(GetCompatibleGrantTypes))]
    public void IsValid_WithCompatibleGrantTypes_ReturnsSuccess(List<string> grants)
    {
        // Act
        var result = _attribute.GetValidationResult(grants, _context);

        // Assert
        Assert.That(result, Is.EqualTo(ValidationResult.Success));
    }

    [Test]
    public void IsValid_WithMultipleIncompatiblePairs_ReturnsErrorWithAllPairs()
    {
        // Arrange
        // all incompatible pairs
        var grantTypes = ClientGrantTypeNames.IncompatibleGrantPairs.SelectMany(p => new[] { p.Key, p.Value }).ToHashSet();

        // Act
        var result = _attribute.GetValidationResult(grantTypes, _context);

        // Assert
        // Each incompatible pair is represented in the error message
        Assert.That(result, Is.Not.Null);
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result.ErrorMessage, Is.Not.Empty);
            foreach (var pair in ClientGrantTypeNames.IncompatibleGrantPairs)
            {
                var g1Name = ClientGrantTypeNames.AllGrantTypes[pair.Key];
                var g2Name = ClientGrantTypeNames.AllGrantTypes[pair.Value];
                Assert.That(result.ErrorMessage, Does.Contain($"'{g1Name}' and '{g2Name}'"));
            }
            Assert.That(result.MemberNames, Contains.Item("AllowedGrantTypes"));
        }
    }

    [TestCaseSource(nameof(GetInvalidTypedObjects))]
    public void IsValid_WithNonEnumerableValue_ReturnsError(object value)
    {
        // Act
        var result = _attribute.GetValidationResult(value, _context);

        // Assert
        Assert.That(result, Is.Not.Null);
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result!.ErrorMessage, Does.Contain("Value is not of the expected type (IEnumerable<string>)."));
            Assert.That(result.MemberNames, Contains.Item("AllowedGrantTypes"));
        }
    }

    [TestCaseSource(nameof(GetIncompatibleGrantTypes))]
    public void IsValid_WitIncompatibleGrants_ReturnsError(List<string> grants)
    {
        // Act
        var result = _attribute.GetValidationResult(grants, _context);

        // Assert
        Assert.That(result, Is.Not.Null);
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result.ErrorMessage, Does.Contain(ClientGrantTypeNames.AllGrantTypes[grants[0]]));
            Assert.That(result.ErrorMessage, Does.Contain(ClientGrantTypeNames.AllGrantTypes[grants[1]]));
            Assert.That(result.MemberNames, Contains.Item("AllowedGrantTypes"));
        }
    }

    private static IEnumerable<TestCaseData> GetIncompatibleGrantTypes()
    {
        foreach (var (g1, g2) in ClientGrantTypeNames.IncompatibleGrantPairs)
        {
            yield return new TestCaseData(new List<string>() { g1, g2 });
            yield return new TestCaseData(new List<string> { g2, g1 });
        }
    }

    private static IEnumerable<TestCaseData> GetCompatibleGrantTypes()
    {
        yield return new TestCaseData(new List<string>() { ClientGrantTypeNames.Grant_Code, ClientGrantTypeNames.Grant_TokenExchange });
        yield return new TestCaseData(new List<string>() { ClientGrantTypeNames.Grant_ClientCredentials, ClientGrantTypeNames.Grant_TokenExchange });
    }

    private static IEnumerable<TestCaseData> GetInvalidTypedObjects()
    {
        yield return new TestCaseData(123.0);
        yield return new TestCaseData("1234");
    }
}
