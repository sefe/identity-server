// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

using NUnit.Framework;
using System;
using System.Linq;
using IdentityServer.Core.Serilog.Extensions;

namespace IdentityServer.Core.Serilog.Test
{
    public class TradingSerilogSystemContextDataExtensionsTests
    {
        private class Sample
        {
            public string? PropA { get; set; }
            public int PropB { get; set; }
            public string? NullableProp { get; set; }
        }

        [Test]
        public void DeconstructToContextPropertiesWithPrefix_ReturnsKeyValuePairs_WithDefaultPrefixAndTypeName()
        {
            // Arrange
            var sample = new Sample { PropA = "value", PropB =123, NullableProp = "notnull" };

            // Act
            var result = sample.DeconstructToContextPropertiesWithPrefix<Sample>().ToList();

            // Assert
            Assert.That(result, Has.Count.EqualTo(3));
            using (Assert.EnterMultipleScope())
            {
                Assert.That(result.Any(kv => kv.Key == "Ctx.Sample.PropA" && (string)kv.Value == "value"));
                Assert.That(result.Any(kv => kv.Key == "Ctx.Sample.PropB" && (int)kv.Value == 123));
                Assert.That(result.Any(kv => kv.Key == "Ctx.Sample.NullableProp" && (string)kv.Value == "notnull"));
            }
        }

        [Test]
        public void DeconstructToContextPropertiesWithPrefix_IncludesAlias_WhenAliasProvided()
        {
            // Arrange
            var sample = new Sample { PropA = "v", PropB =1 };

            // Act
            var result = sample.DeconstructToContextPropertiesWithPrefix<Sample>(alias: "System").ToList();

            // Assert
            Assert.That(result, Has.Count.EqualTo(2));
            using (Assert.EnterMultipleScope())
            {
                Assert.That(result.Any(kv => kv.Key == "Ctx.Sample.System.PropA"));
                Assert.That(result.Any(kv => kv.Key == "Ctx.Sample.System.PropB"));
            }
        }

        [Test]
        public void DeconstructToContextPropertiesWithPrefix_OmitsNullValues()
        {
            // Arrange
            var sample = new Sample { PropA = null, PropB =5, NullableProp = null };

            // Act
            var result = sample.DeconstructToContextPropertiesWithPrefix<Sample>().ToList();

            // Assert
            Assert.That(result, Has.Count.EqualTo(1));
            using (Assert.EnterMultipleScope())
            {
                Assert.That(result[0].Key, Is.EqualTo("Ctx.Sample.PropB"));
                Assert.That(result[0].Value, Is.EqualTo(5));
            }
        }
    }
}
