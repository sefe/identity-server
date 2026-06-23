// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

using Serilog.Events;
using IdentityServer.Core.Serilog.Extensions;

namespace IdentityServer.Core.Serilog.Test;

public class LogEventPropertyExtensionTests
{
    private static StructureValue Structure(params (string Name, LogEventPropertyValue Value)[] properties)
    => new(properties.Select(p => new LogEventProperty(p.Name, p.Value)).ToList(), "MyTypeTag");

    private static StructureValue StructureNoType(params (string Name, LogEventPropertyValue Value)[] properties)
    => new(properties.Select(p => new LogEventProperty(p.Name, p.Value)).ToList());

    private static DictionaryValue Dictionary(params (string Key, LogEventPropertyValue Value)[] entries)
    => new(entries.Select(e => new KeyValuePair<ScalarValue, LogEventPropertyValue>(new ScalarValue(e.Key), e.Value)).ToList());

    private static SequenceValue Sequence(params LogEventPropertyValue[] values)
    => new(values.ToList());

    private static ScalarValue Scalar(object value) => new(value);

    [Test]
    public void AsObject_WithScalar_ReturnsUnderlyingValue()
    {
        // Arrange
        var value = Scalar("hello");
        // Act
        var obj = value.AsObject();
        // Assert
        Assert.That(obj, Is.EqualTo("hello"));
    }

    [Test]
    public void AsObject_WithSequence_ReturnsConvertedArray()
    {
        // Arrange
        var value = Sequence(Scalar(1), Scalar(2), Scalar(3));
        // Act
        var obj = value.AsObject();
        // Assert
        Assert.That(obj, Is.EqualTo(new object[] { 1, 2, 3 }));
    }

    [Test]
    public void AsObject_WithEmptySequence_ReturnsEmptyArray()
    {
        // Arrange
        var value = Sequence();
        // Act
        var obj = value.AsObject();
        // Assert
        Assert.That(obj, Is.EqualTo(Array.Empty<object>()));
    }

    [Test]
    public void AsObject_WithDictionary_ReturnsConvertedDictionary()
    {
        // Arrange
        var value = Dictionary(("Key1", Scalar("V1")), ("Key2", Scalar(10)));
        // Act
        var obj = value.AsObject();
        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(obj, Is.InstanceOf<Dictionary<string, object>>());
            var dict = (Dictionary<string, object>)obj;
            Assert.That(dict["Key1"], Is.EqualTo("V1"));
            Assert.That(dict["Key2"], Is.EqualTo(10));
        }
    }

    [Test]
    public void AsObject_WithEmptyDictionary_ReturnsEmptyDictionary()
    {
        // Arrange
        var value = Dictionary();
        // Act
        var obj = value.AsObject();
        using (Assert.EnterMultipleScope())
        {
            // Assert
            Assert.That(obj, Is.InstanceOf<Dictionary<string, object>>());
            Assert.That(((Dictionary<string, object>)obj), Is.Empty);
        }
    }

    [Test]
    public void AsObject_WithStructure_IncludesTypeAndProperties()
    {
        // Arrange
        var value = Structure(("A", Scalar(1)), ("B", Scalar("text")));
        // Act
        var obj = value.AsObject();
        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(obj, Is.InstanceOf<Dictionary<string, object>>());
            var dict = (Dictionary<string, object>)obj;
            Assert.That(dict["A"], Is.EqualTo(1));
            Assert.That(dict["B"], Is.EqualTo("text"));
            Assert.That(dict["$type"], Is.EqualTo("MyTypeTag"));
        }
    }

    [Test]
    public void AsObject_WithStructureNoType_DoesNotIncludeTypeKey()
    {
        // Arrange
        var value = StructureNoType(("A", Scalar(5)));
        // Act
        var obj = value.AsObject();
        // Assert
        var dict = (Dictionary<string, object>)obj;
        Assert.That(dict.ContainsKey("$type"), Is.False);
    }

    [Test]
    public void AsObject_WithNestedStructure_RecursivelyConverts()
    {
        // Arrange
        var inner = Structure(("X", Scalar("xval")));
        var outer = Structure(("Inner", inner), ("Num", Scalar(9)));
        // Act
        var obj = outer.AsObject();
        // Assert
        using (Assert.EnterMultipleScope())
        {
            var dict = (Dictionary<string, object>)obj;
            Assert.That(dict["Num"], Is.EqualTo(9));
            Assert.That(dict["$type"], Is.EqualTo("MyTypeTag"));
            var innerDict = (Dictionary<string, object>)dict["Inner"]; // nested structure
            Assert.That(innerDict["X"], Is.EqualTo("xval"));
            Assert.That(innerDict["$type"], Is.EqualTo("MyTypeTag"));
        }
    }
}
