// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

using NUnit.Framework;
using Serilog.Events;
using Serilog.Parsing;
using System;
using System.Collections.Generic;
using System.Linq;
using IdentityServer.Core.Serilog.Extensions;
using IdentityServer.Core.Serilog.Entities;

namespace IdentityServer.Core.Serilog.Test
{
    public class LogEventExtensionsTests
    {
        private static LogEvent CreateLogEvent(IEnumerable<LogEventProperty> properties, string message = "Test")
        {
            var parser = new MessageTemplateParser();
            var template = parser.Parse(message);
            return new LogEvent(DateTimeOffset.UtcNow, LogEventLevel.Information, null, template, properties.ToList());
        }

        private static LogEventProperty Scalar(string name, object value) => new(name, new ScalarValue(value));
        private static LogEventProperty Structure(string name, IEnumerable<LogEventProperty> props, string typeTag) => new(name, new StructureValue(props.ToList(), typeTag));
        private static LogEventProperty Sequence(string name, IEnumerable<LogEventPropertyValue> values) => new(name, new SequenceValue(values.ToList()));

        private class CustomContext
        {
            public string? Machine { get; set; }
            public int Count { get; set; }
            public string[]? Tags { get; set; }
        }

        [Test]
        public void GetPropertyOrDefault_WithExistingScalar_ReturnsValue()
        {
            // Arrange
            var logEvent = CreateLogEvent(new[] { Scalar("Number", 42) });

            // Act
            var value = logEvent.GetPropertyOrDefault<int>("Number");

            // Assert
            Assert.That(value, Is.EqualTo(42));
        }

        [Test]
        public void GetPropertyOrDefault_IfMissing_ReturnsDefault()
        {
            // Arrange
            var logEvent = CreateLogEvent(Array.Empty<LogEventProperty>());

            // Act
            var value = logEvent.GetPropertyOrDefault<int>("Missing");

            // Assert
            Assert.That(value, Is.Default);
        }

        [Test]
        public void TryGetProperty_WithMatchingType_ReturnsTrueAndValue()
        {
            // Arrange
            var logEvent = CreateLogEvent(new[] { Scalar("User", "alice") });

            // Act
            var success = logEvent.TryGetProperty<string>("User", out var value);

            // Assert
            using (Assert.EnterMultipleScope())
            {
                Assert.That(success, Is.True);
                Assert.That(value, Is.EqualTo("alice"));
            }
        }

        [Test]
        public void TryGetProperty_WithTypeMismatch_ReturnsFalse()
        {
            // Arrange
            var logEvent = CreateLogEvent(new[] { Scalar("Age", 30) });

            // Act
            var success = logEvent.TryGetProperty<string>("Age", out var value);

            // Assert
            using (Assert.EnterMultipleScope())
            {
                Assert.That(success, Is.False);
                Assert.That(value, Is.Null);
            }
        }

        [Test]
        public void TryGetCustomAppProperties_WithMixedProperties_FiltersOutStructureValuesAndKnownProps()
        {
            // Arrange
            var coreStructure = Scalar("TestProp", "TestPropValue"); // should be the only one in result
            var appStructure = Structure("AppProp", new[] { Scalar("Inner", 5) }, "OtherTag");
            var sourceContext = Scalar(KnownSerilogPropertyNames.SourceContext, "Logger.Name"); // known serilog property
            var logEvent = CreateLogEvent(new[] { coreStructure, appStructure, sourceContext });

            // Act
            var success = logEvent.TryGetCustomAppProperties(out var dict);

            // Assert
            using (Assert.EnterMultipleScope())
            {
                Assert.That(success, Is.True);
                Assert.That(dict.ContainsKey("TestProp"), Is.True);
                Assert.That(dict.ContainsKey("AppProp"), Is.False); // filtered
                Assert.That(dict.ContainsKey(KnownSerilogPropertyNames.SourceContext), Is.False); // filtered
            }
        }

        [Test]
        public void TryGetPropertyFromContext_WithValidContext_ReconstructsObjectAndAlias()
        {
            // Arrange
            var props = new List<LogEventProperty>
            {
                Scalar("Ctx.CustomContext.AliasX.Machine", "HOST1"),
                Scalar("Ctx.CustomContext.AliasX.Count", 7)
            };
            var logEvent = CreateLogEvent(props);

            // Act
            var success = logEvent.TryGetPropertyFromContext<CustomContext>(out var contextProp);

            // Assert
            using (Assert.EnterMultipleScope())
            {
                Assert.That(success, Is.True);
                Assert.That(contextProp, Is.Not.Null);
                Assert.That(contextProp!.Name, Is.EqualTo("AliasX"));
                Assert.That(contextProp?.Value?.Machine, Is.EqualTo("HOST1"));
                Assert.That(contextProp?.Value?.Count, Is.EqualTo(7));
            }
        }
        private static readonly string[] _expected = new[] { "one", "two" };

        [Test]
        public void TryGetPropertyFromContext_WithArrayProperty_ReconstructsArray()
        {
            // Arrange
            var tagsSequence = Sequence("Ctx.CustomContext.AliasY.Tags", new LogEventPropertyValue[]
            {
                new ScalarValue("one"),
                new ScalarValue("two")
            });
            var logEvent = CreateLogEvent(new[] { tagsSequence });

            // Act
            var success = logEvent.TryGetPropertyFromContext<CustomContext>(out var contextProp);

            // Assert
            using (Assert.EnterMultipleScope())
            {
                Assert.That(success, Is.True);
                Assert.That(contextProp, Is.Not.Null);
                Assert.That(contextProp!.Value, Is.Not.Null);
                Assert.That(contextProp.Value!.Tags, Is.EquivalentTo(_expected));
            }
        }

        [Test]
        public void TryGetPropertyFromContext_IfNoContextKeys_ReturnsFalse()
        {
            // Arrange
            var logEvent = CreateLogEvent(new[] { Scalar("Unrelated", 123) });

            // Act
            var success = logEvent.TryGetPropertyFromContext<CustomContext>(out var ctx);

            // Assert
            using (Assert.EnterMultipleScope())
            {
                Assert.That(success, Is.False);
                Assert.That(ctx, Is.Null);
            }
        }
    }
}
