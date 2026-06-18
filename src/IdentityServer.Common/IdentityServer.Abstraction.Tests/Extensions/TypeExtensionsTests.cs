using IdentityServer.Abstraction.Extensions;

namespace IdentityServer.Abstraction.Tests.Extensions;

[TestFixture]
public class TypeExtensionsTests
{
    [Test]
    public void GetTypeDisplayName_WithNonGenericType_ReturnsTypeName()
    {
        // Arrange
        var type = typeof(string);

        // Act
        var result = type.GetTypeDisplayName();

        // Assert
        Assert.That(result, Is.EqualTo("String"));
    }

    [Test]
    public void GetTypeDisplayName_WithSimpleClass_ReturnsClassName()
    {
        // Arrange
        var type = typeof(TypeExtensionsTests);

        // Act
        var result = type.GetTypeDisplayName();

        // Assert
        Assert.That(result, Is.EqualTo("TypeExtensionsTests"));
    }

    [Test]
    public void GetTypeDisplayName_WithSimpleGenericType_ReturnsGenericTypeName()
    {
        // Arrange
        var type = typeof(List<string>);

        // Act
        var result = type.GetTypeDisplayName();

        // Assert
        Assert.That(result, Is.EqualTo("List<String>"));
    }

    [Test]
    public void GetTypeDisplayName_WithMultipleGenericArguments_ReturnsCorrectFormat()
    {
        // Arrange
        var type = typeof(Dictionary<string, int>);

        // Act
        var result = type.GetTypeDisplayName();

        // Assert
        Assert.That(result, Is.EqualTo("Dictionary<String,Int32>"));
    }

    [Test]
    public void GetTypeDisplayName_WithNestedGenericType_ReturnsNestedFormat()
    {
        // Arrange
        var type = typeof(List<List<string>>);

        // Act
        var result = type.GetTypeDisplayName();

        // Assert
        Assert.That(result, Is.EqualTo("List<List<String>>"));
    }

    [Test]
    public void GetTypeDisplayName_WithComplexNestedGenericType_ReturnsCorrectFormat()
    {
        // Arrange
        var type = typeof(Dictionary<string, List<int>>);

        // Act
        var result = type.GetTypeDisplayName();

        // Assert
        Assert.That(result, Is.EqualTo("Dictionary<String,List<Int32>>"));
    }

    [Test]
    public void GetTypeDisplayName_WithDeeplyNestedGenericType_ReturnsCorrectFormat()
    {
        // Arrange
        var type = typeof(Dictionary<List<string>, Dictionary<int, List<bool>>>);

        // Act
        var result = type.GetTypeDisplayName();

        // Assert
        Assert.That(result, Is.EqualTo("Dictionary<List<String>,Dictionary<Int32,List<Boolean>>>"));
    }

    [Test]
    public void GetTypeDisplayName_WithNullableType_ReturnsCorrectFormat()
    {
        // Arrange
        var type = typeof(int?);

        // Act
        var result = type.GetTypeDisplayName();

        // Assert
        Assert.That(result, Is.EqualTo("Nullable<Int32>"));
    }

    [Test]
    public void GetTypeDisplayName_WithValueTuple_ReturnsCorrectFormat()
    {
        // Arrange
        var type = typeof(ValueTuple<string, int>);

        // Act
        var result = type.GetTypeDisplayName();

        // Assert
        Assert.That(result, Is.EqualTo("ValueTuple<String,Int32>"));
    }

    [Test]
    public void GetTypeDisplayName_WithTask_ReturnsCorrectFormat()
    {
        // Arrange
        var type = typeof(Task<string>);

        // Act
        var result = type.GetTypeDisplayName();

        // Assert
        Assert.That(result, Is.EqualTo("Task<String>"));
    }

    [Test]
    public void GetTypeDisplayName_WithIEnumerable_ReturnsCorrectFormat()
    {
        // Arrange
        var type = typeof(IEnumerable<int>);

        // Act
        var result = type.GetTypeDisplayName();

        // Assert
        Assert.That(result, Is.EqualTo("IEnumerable<Int32>"));
    }

    [Test]
    public void GetTypeDisplayName_WithArray_ReturnsArrayTypeName()
    {
        // Arrange
        var type = typeof(int[]);

        // Act
        var result = type.GetTypeDisplayName();

        // Assert
        Assert.That(result, Is.EqualTo("Int32[]"));
    }

    [Test]
    public void GetTypeDisplayName_WithMultidimensionalArray_ReturnsCorrectFormat()
    {
        // Arrange
        var type = typeof(int[,]);

        // Act
        var result = type.GetTypeDisplayName();

        // Assert
        Assert.That(result, Is.EqualTo("Int32[,]"));
    }

    [Test]
    public void GetTypeDisplayName_WithJaggedArray_ReturnsCorrectFormat()
    {
        // Arrange
        var type = typeof(int[][]);

        // Act
        var result = type.GetTypeDisplayName();

        // Assert
        Assert.That(result, Is.EqualTo("Int32[][]"));
    }

    [Test]
    public void GetTypeDisplayName_WithPrimitiveTypes_ReturnsCorrectNames()
    {
        // Arrange & Act & Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(typeof(int).GetTypeDisplayName(), Is.EqualTo("Int32"));
            Assert.That(typeof(long).GetTypeDisplayName(), Is.EqualTo("Int64"));
            Assert.That(typeof(double).GetTypeDisplayName(), Is.EqualTo("Double"));
            Assert.That(typeof(bool).GetTypeDisplayName(), Is.EqualTo("Boolean"));
            Assert.That(typeof(decimal).GetTypeDisplayName(), Is.EqualTo("Decimal"));
        }
    }
}
