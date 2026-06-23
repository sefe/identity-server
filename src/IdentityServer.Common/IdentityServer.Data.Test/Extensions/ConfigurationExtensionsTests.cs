// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

using Microsoft.Extensions.Configuration;
using IdentityServer.Abstraction.Exceptions;
using IdentityServer.Core.Extensions;

namespace IdentityServer.Data.Test.Extensions;

[TestFixture]
public class ConfigurationExtensionsTests
{
    private IConfigurationBuilder _configurationBuilder;

    [SetUp]
    public void SetUp()
    {
        _configurationBuilder = new ConfigurationBuilder();
    }

    [Test]
    public void DirectGetSection_WithValidSection_ReturnsConfiguredObject()
    {
        // Arrange
        var testData = new Dictionary<string, string>
        {
            { "TestSection:Name", "Test Name" },
            { "TestSection:Value", "42" },
            { "TestSection:IsEnabled", "true" }
        };

        var configuration = _configurationBuilder
            .AddInMemoryCollection(testData)
            .Build();

        // Act
        var result = configuration.DirectGetSection<TestConfig>("TestSection");

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result, Is.Not.Null);
            Assert.That(result.Name, Is.EqualTo("Test Name"));
            Assert.That(result.Value, Is.EqualTo(42));
            Assert.That(result.IsEnabled, Is.True);
        }
    }

    [Test]
    public void DirectGetSection_WithEmptySection_ThrowsIdentityServerException()
    {
        // Arrange
        var configuration = _configurationBuilder
            .AddInMemoryCollection(new Dictionary<string, string>())
            .Build();

        // Act & Assert
        var ex = Assert.Throws<IdentityServerException>(() => 
            configuration.DirectGetSection<TestConfig>("NonExistentSection"));
        
        Assert.That(ex.Message, Is.EqualTo("Unable to retrieve the section 'NonExistentSection' from the configuration"));
    }

    [Test]
    public void DirectGetSection_WithPartiallyConfiguredSection_ReturnsObjectWithDefaultValues()
    {
        // Arrange
        var testData = new Dictionary<string, string>
        {
            { "PartialSection:Name", "Partial Name" }
            // Missing Value and IsEnabled properties
        };

        var configuration = _configurationBuilder
            .AddInMemoryCollection(testData)
            .Build();

        // Act
        var result = configuration.DirectGetSection<TestConfig>("PartialSection");

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result, Is.Not.Null);
            Assert.That(result.Name, Is.EqualTo("Partial Name"));
            Assert.That(result.Value, Is.Zero); // Default int value
            Assert.That(result.IsEnabled, Is.False); // Default bool value
        }
    }

    [Test]
    public void DirectGetSection_WithNestedComplexObject_ReturnsConfiguredObject()
    {
        // Arrange
        var testData = new Dictionary<string, string>
        {
            { "ComplexSection:Name", "Complex Config" },
            { "ComplexSection:Nested:InnerValue", "Inner Data" },
            { "ComplexSection:Nested:InnerNumber", "123" },
            { "ComplexSection:Items:0", "Item1" },
            { "ComplexSection:Items:1", "Item2" }
        };

        var configuration = _configurationBuilder
            .AddInMemoryCollection(testData)
            .Build();

        // Act
        var result = configuration.DirectGetSection<ComplexTestConfig>("ComplexSection");

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result, Is.Not.Null);
            Assert.That(result.Name, Is.EqualTo("Complex Config"));
            Assert.That(result.Nested, Is.Not.Null);
            Assert.That(result.Nested.InnerValue, Is.EqualTo("Inner Data"));
            Assert.That(result.Nested.InnerNumber, Is.EqualTo(123));
            Assert.That(result.Items, Is.Not.Null);
            Assert.That(result.Items, Has.Count.EqualTo(2));
            Assert.That(result.Items[0], Is.EqualTo("Item1"));
            Assert.That(result.Items[1], Is.EqualTo("Item2"));
        }
    }

    [Test]
    public void DirectGetSection_WithEmptyStringSection_ThrowsIdentityServerException()
    {
        // Arrange
        var configuration = _configurationBuilder
            .AddInMemoryCollection(new Dictionary<string, string>())
            .Build();

        // Act & Assert
        var ex = Assert.Throws<IdentityServerException>(() => 
            configuration.DirectGetSection<TestConfig>(""));
        
        Assert.That(ex.Message, Is.EqualTo("Unable to retrieve the section '' from the configuration"));
    }

    [Test]
    public void DirectGetSection_WithValidSectionAndGenericType_ReturnsCorrectType()
    {
        // Arrange
        var testData = new Dictionary<string, string>
        {
            { "GenericSection:Property", "Generic Value" }
        };

        var configuration = _configurationBuilder
            .AddInMemoryCollection(testData)
            .Build();

        // Act
        var result = configuration.DirectGetSection<GenericTestConfig<string>>("GenericSection");

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result, Is.Not.Null);
            Assert.That(result, Is.InstanceOf<GenericTestConfig<string>>());
            Assert.That(result.Property, Is.EqualTo("Generic Value"));
        }
    }

    // Test configuration classes
    public class TestConfig
    {
        public string Name { get; set; } = string.Empty;
        public int Value { get; set; }
        public bool IsEnabled { get; set; }
    }

    public class ComplexTestConfig
    {
        public string Name { get; set; } = string.Empty;
        public NestedConfig Nested { get; set; } = new();
        public List<string> Items { get; set; } = new();
    }

    public class NestedConfig
    {
        public string InnerValue { get; set; } = string.Empty;
        public int InnerNumber { get; set; }
    }

    public class GenericTestConfig<T>
    {
        public T Property { get; set; }
    }
}
