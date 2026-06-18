using NUnit.Framework;
using Serilog.Events;
using Serilog.Parsing;
using Serilog.Core;
using System;
using System.Collections.Generic;
using IdentityServer.Core.Serilog;
using IdentityServer.Core.Serilog.Entities;

namespace IdentityServer.Core.Serilog.Test
{
    public class TradingSerilogEnricherTests
    {
        private static LogEvent CreateEmptyLogEvent(string message = "Test")
        {
            var parser = new MessageTemplateParser();
            var template = parser.Parse(message);
            return new LogEvent(DateTimeOffset.UtcNow, LogEventLevel.Information, null, template, new List<LogEventProperty>());
        }

        [Test]
        public void Enrich_WithDefaultContext_AddsExpectedProperties()
        {
            // Arrange
            var enricher = new TradingSerilogEnricher(_ => { });
            var logEvent = CreateEmptyLogEvent();

            // Act
            enricher.Enrich(logEvent, null!);

            // Assert
            // Expect at least Version, CoreVersion, ProcessUserIdentity
            using (Assert.EnterMultipleScope())
            {
                Assert.That(logEvent.Properties.ContainsKey("Ctx.SystemContextData.System.Version"), Is.True);
                Assert.That(logEvent.Properties.ContainsKey("Ctx.SystemContextData.System.CoreVersion"), Is.True);
                Assert.That(logEvent.Properties.ContainsKey("Ctx.SystemContextData.System.ProcessUserIdentity"), Is.True);
            }
        }

        [Test]
        public void Enrich_WithConfigurationOverride_UsesUpdatedValue()
        {
            // Arrange
            var enricher = new TradingSerilogEnricher(c =>
            {
                c.MachineName = "OVERRIDE-MACHINE";
            });
            var logEvent = CreateEmptyLogEvent();

            // Act
            enricher.Enrich(logEvent, null!);

            // Assert
            Assert.That(logEvent.Properties["Ctx.SystemContextData.System.MachineName"].ToString(), Does.Contain("OVERRIDE-MACHINE"));
        }

        [Test]
        public void Enrich_WithNullOptionalProperty_SkipsIt()
        {
            // Arrange
            var enricher = new TradingSerilogEnricher(c =>
            {
                c.MachineName = null; // ensure null
            });
            var logEvent = CreateEmptyLogEvent();

            // Act
            enricher.Enrich(logEvent, null!);

            // Assert
            Assert.That(logEvent.Properties.ContainsKey("Ctx.SystemContextData.System.MachineName"), Is.False);
        }

        [Test]
        public void Enrich_IfPropertyAlreadyExists_DoesNotOverwrite()
        {
            // Arrange
            var logEvent = CreateEmptyLogEvent();
            // pre-add Version property with dummy value
            logEvent.AddPropertyIfAbsent(new LogEventProperty("Ctx.SystemContextData.System.Version", new ScalarValue("PRESET")));

            var enricher = new TradingSerilogEnricher(_ => { });

            // Act
            enricher.Enrich(logEvent, null!);

            // Assert
            Assert.That(logEvent.Properties["Ctx.SystemContextData.System.Version"].ToString(), Is.EqualTo("\"PRESET\""));
        }

        [Test]
        public void Enrich_OnMultipleCalls_DoesNotDuplicateKeys()
        {
            // Arrange
            var enricher = new TradingSerilogEnricher(_ => { });
            var logEvent = CreateEmptyLogEvent();

            // Act
            enricher.Enrich(logEvent, null!);
            enricher.Enrich(logEvent, null!);

            // Assert
            // Count each key once
            var keys = logEvent.Properties.Keys;
            Assert.That(keys, Is.Unique);
        }
    }
}
