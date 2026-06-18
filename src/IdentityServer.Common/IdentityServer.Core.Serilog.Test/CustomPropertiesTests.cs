using NUnit.Framework;
using System;
using System.Collections.Generic;
using IdentityServer.Core.Serilog.Entities;

namespace IdentityServer.Core.Serilog.Test;

[TestFixture]
public class CustomPropertiesTests
{
    [Test]
    public void Ctor_OnInitialization_CreatesEmptyCollection()
    {
        // Arrange & Act
        var props = new CustomProperties();

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(props, Is.Empty);
            Assert.That(props.Keys, Is.Empty);
            Assert.That(props.Values, Is.Empty);
        }
    }

    [Test]
    public void Indexer_WithNewKey_SetsAndGetsValue()
    {
        // Arrange
        var props = new CustomProperties
        {
            // Act
            ["k1"] = 123
        };

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(props, Has.Count.EqualTo(1));
            Assert.That(props["k1"], Is.EqualTo(123));
        }
    }

    [Test]
    public void Indexer_WithExistingKey_OverwritesValue()
    {
        // Arrange
        var props = new CustomProperties { {"k1",1} };

        // Act
        props["k1"] = 42;

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(props, Has.Count.EqualTo(1));
            Assert.That(props["k1"], Is.EqualTo(42));
        }
    }

    [Test]
    public void Indexer_OnMissingKey_ThrowsKeyNotFoundException()
    {
        // Arrange
        var props = new CustomProperties();

        // Act & Assert
        Assert.That(() => _ = props["missing"], Throws.TypeOf<KeyNotFoundException>());
    }

    [Test]
    public void Add_WithUniqueKey_AddsEntry()
    {
        // Arrange
        var props = new CustomProperties
        {
            // Act
            { "k1", 10 }
        };

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(props, Has.Count.EqualTo(1));
            Assert.That(props.ContainsKey("k1"), Is.True);
            Assert.That(props["k1"], Is.EqualTo(10));
        }
    }

    [Test]
    public void Add_WithDuplicateKey_ThrowsArgumentException()
    {
        // Arrange
        var props = new CustomProperties { {"k1",10} };

        // Act & Assert
        Assert.That(() => props.Add("k1", 20), Throws.TypeOf<ArgumentException>());
    }

    [Test]
    public void ContainsKey_WithExistingKey_ReturnsTrue()
    {
        // Arrange
        var props = new CustomProperties { {"k1",10} };

        // Act
        var result = props.ContainsKey("k1");

        // Assert
        Assert.That(result, Is.True);
    }

    [Test]
    public void ContainsKey_WithMissingKey_ReturnsFalse()
    {
        // Arrange
        var props = new CustomProperties();

        // Act
        var result = props.ContainsKey("missing");

        // Assert
        Assert.That(result, Is.False);
    }

    [Test]
    public void TryGetValue_WithExistingKey_ReturnsTrueAndOutputsValue()
    {
        // Arrange
        var props = new CustomProperties { {"k1",99} };

        // Act
        var success = props.TryGetValue("k1", out var value);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(success, Is.True);
            Assert.That(value, Is.EqualTo(99));
        }
    }

    [Test]
    public void TryGetValue_WithMissingKey_ReturnsFalseAndOutputsDefault()
    {
        // Arrange
        var props = new CustomProperties();

        // Act
        var success = props.TryGetValue("k1", out var value);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(success, Is.False);
            Assert.That(value, Is.Null);
        }
    }

    [Test]
    public void Remove_WithExistingKey_RemovesEntry()
    {
        // Arrange
        var props = new CustomProperties { {"k1",10} };

        // Act
        var removed = props.Remove("k1");

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(removed, Is.True);
            Assert.That(props.ContainsKey("k1"), Is.False);
            Assert.That(props, Is.Empty);
        }
    }

    [Test]
    public void Remove_WithMissingKey_ReturnsFalse()
    {
        // Arrange
        var props = new CustomProperties();

        // Act
        var removed = props.Remove("k1");

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(removed, Is.False);
            Assert.That(props, Is.Empty);
        }
    }

    [Test]
    public void Add_KeyValuePair_WithUniqueKey_AddsEntry()
    {
        // Arrange
        var props = new CustomProperties();
        var kvp = new KeyValuePair<string, object>("k1", 5);

        // Act
        props.Add(kvp);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(props, Has.Count.EqualTo(1));
            Assert.That(props, Does.Contain(kvp));
            Assert.That(props["k1"], Is.EqualTo(5));
        }
    }

    [Test]
    public void Contains_WithMismatchedValue_ReturnsFalse()
    {
        // Arrange
        var props = new CustomProperties { {"k1",5} };
        var different = new KeyValuePair<string, object>("k1", 7);

        // Act
        var contains = props.Contains(different);

        // Assert
        Assert.That(contains, Is.False);
    }

    [Test]
    public void CopyTo_WithSufficientSpace_CopiesItems()
    {
        // Arrange
        var props = new CustomProperties { {"a",1},{"b",2} };
        var array = new KeyValuePair<string, object>[4];

        // Act
        props.CopyTo(array, 1);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(array[1].Key, Is.EqualTo("a"));
            Assert.That(array[1].Value, Is.EqualTo(1));
            Assert.That(array[2].Key, Is.EqualTo("b"));
            Assert.That(array[2].Value, Is.EqualTo(2));
        }
    }

    [Test]
    public void CopyTo_WithInsufficientSpace_ThrowsArgumentException()
    {
        // Arrange
        var props = new CustomProperties { {"a",1} };
        var array = new KeyValuePair<string, object>[1];

        // Act & Assert
        Assert.That(() => props.CopyTo(array, 1), Throws.TypeOf<ArgumentException>());
    }

    [Test]
    public void Clear_OnPopulatedCollection_RemovesAll()
    {
        // Arrange
        var props = new CustomProperties { {"a",1},{"b",2} };

        // Act
        props.Clear();

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(props, Is.Empty);
            Assert.That(props.Keys, Is.Empty);
            Assert.That(props.Values, Is.Empty);
        }
    }

    [Test]
    public void Enumerator_OnPopulatedCollection_IteratesAll()
    {
        // Arrange
        var props = new CustomProperties { {"a",1},{"b",2} };

        // Act
        var collected = new List<string>();
        foreach (var kvp in props)
        {
            collected.Add(kvp.Key);
        }

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(collected, Has.Count.EqualTo(2));
            Assert.That(collected, Does.Contain("a"));
            Assert.That(collected, Does.Contain("b"));
        }
    }
}
