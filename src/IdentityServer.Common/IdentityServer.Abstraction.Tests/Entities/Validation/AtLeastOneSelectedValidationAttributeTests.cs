using System.ComponentModel.DataAnnotations;
using IdentityServer.Abstraction.Entities;
using IdentityServer.Abstraction.Entities.Validation;

namespace IdentityServer.Abstraction.Tests.Entities.Validation;

[TestFixture]
public class AtLeastOneSelectedValidationAttributeTests
{
    private AtLeastOneSelectedValidationAttribute _attribute;
    private readonly ValidationContext _context = new(new object()) { MemberName = "TestProperty" };
    private static readonly string[] _expectedMemberNames = new[] { "TestProperty"};

    [SetUp]
    public void SetUp()
    {
        _attribute = new AtLeastOneSelectedValidationAttribute();
    }

    [Test]
    public void IsValid_WithAtLeastOneSelected_ReturnsSuccess()
    {
        // Arrange
        var items = new List<Selectable>
        {
            new() { IsSelected = false, DisplayName ="1" },
            new() { IsSelected = true, DisplayName = "2" }
        };

        // Act
        var result = _attribute.GetValidationResult(items, _context);

        // Assert
        Assert.That(result, Is.EqualTo(ValidationResult.Success));
    }

    [Test]
    public void IsValid_WithAtLeastOneSelectedValue_ReturnsSuccess()
    {
        // Arrange
        var items = new List<SelectableValue<string>>
        {
            new() { IsSelected = false, DisplayName="1", Value = "1" },
            new() { IsSelected = true, DisplayName= "2", Value = "2" }
        };

        // Act
        var result = _attribute.GetValidationResult(items, _context);

        // Assert
        Assert.That(result, Is.EqualTo(ValidationResult.Success));
    }

    [Test]
    public void IsValid_WithNoneSelected_ReturnsValidationResultWithErrorMessage()
    {
        // Arrange
        var items = new List<Selectable>
        {
            new() { IsSelected = false, DisplayName="1" },
            new() { IsSelected = false,DisplayName= "2" }
        };

        // Act
        var result = _attribute.GetValidationResult(items, _context);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result, Is.Not.Null);
            Assert.That(result?.ErrorMessage, Is.EqualTo("At least one item must be selected."));
            Assert.That(result?.MemberNames, Is.EquivalentTo(_expectedMemberNames));
        }
    }

    [Test]
    public void IsValid_WithNoneSelectedValue_ReturnsValidationResultWithErrorMessage()
    {
        // Arrange
        var items = new List<SelectableValue<string>>
        {
            new() { IsSelected = false, DisplayName = "1", Value = "1" },
            new() { IsSelected = false,DisplayName = "2", Value = "2" }
        };

        // Act
        var result = _attribute.GetValidationResult(items, _context);

        // Assert
        Assert.That(result, Is.Not.Null);
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result.ErrorMessage, Is.EqualTo("At least one item must be selected."));
            Assert.That(result.MemberNames, Is.EquivalentTo(_expectedMemberNames));
        }
    }

    [Test]
    public void IsValid_WithNullValue_ReturnsSuccess()
    {
        // Act
        var result = _attribute.GetValidationResult(null, _context);

        // Assert
        Assert.That(result, Is.EqualTo(ValidationResult.Success));
    }

    [Test]
    public void IsValid_WithNonEnumerableValue_ReturnsSuccess()
    {
        // Act
        var result = _attribute.GetValidationResult(42, _context);

        // Assert
        Assert.That(result, Is.EqualTo(ValidationResult.Success));
    }

    [Test]
    public void IsValid_WithNonSelectableEnumerable_ReturnsSuccess()
    {
        // Arrange
        var items = new List<string>() { "1" };

        // Act
        var result = _attribute.GetValidationResult(items, _context);

        // Assert
        Assert.That(result, Is.EqualTo(ValidationResult.Success));
    }

}
