// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

using NUnit.Framework;
using System;
using System.Collections.Generic;
using Serilog.Events;
using Serilog.Parsing;
using IdentityServer.Core.Serilog;
using IdentityServer.Core.Serilog.Entities; // Added for KnownSerilogPropertyNames

namespace IdentityServer.Core.Serilog.Test
{
    public class SerilogEventToTradingEventMapperTests
    {
        private readonly MessageTemplateParser _parser = new();

        [Test]
        public void Map_WithBasicProperties_MapsExpectedFields()
        {
            // Arrange
            var timestamp = DateTimeOffset.UtcNow;
            var template = _parser.Parse("Test message");

            var props = new List<LogEventProperty>
            {
                new(KnownSerilogPropertyNames.SourceContext, new ScalarValue("My.Logger")),
                new(KnownSerilogPropertyNames.IdentityName, new ScalarValue("jdoe")),
                new(KnownSerilogPropertyNames.ApplicationName, new ScalarValue("MyApp")),
                new(KnownSerilogPropertyNames.ApplicationId, new ScalarValue("app-1")),
                new(KnownSerilogPropertyNames.ApplicationVersion, new ScalarValue("1.2.3")),
                new(KnownSerilogPropertyNames.RequestId, new ScalarValue("req-123")),
                new(KnownSerilogPropertyNames.CorrelationId, new ScalarValue(Guid.Parse("11111111-1111-1111-1111-111111111111"))),
                new(KnownSerilogPropertyNames.ProcessId, new ScalarValue(42)),
                new(KnownSerilogPropertyNames.ProcessName, new ScalarValue("proc-name")),
                new(KnownSerilogPropertyNames.ThreadId, new ScalarValue(7)),
                new(KnownSerilogPropertyNames.ThreadName, new ScalarValue("thread-1")),
                new(KnownSerilogPropertyNames.MachineName, new ScalarValue("MACHINE")),
            };

            var logEvent = new LogEvent(timestamp, LogEventLevel.Information, exception: null, messageTemplate: template, properties: props);
            var mapper = new SerilogEventToTradingEventMapper("MyApp");

            // Act
            var result = mapper.Map(logEvent);

            // Assert (grouped to gather all failures)
            using (Assert.EnterMultipleScope())
            {
                Assert.That(result, Is.Not.Null);
                Assert.That(result.Timestamp, Is.EqualTo(timestamp));
                Assert.That(result.Message, Is.EqualTo("Test message"));
                Assert.That(result.Log, Is.Not.Null);
                Assert.That(result.Log.Level, Is.EqualTo(LogEventLevel.Information.ToString("F")));
                Assert.That(result.Log.Logger, Is.EqualTo("My.Logger"));

                Assert.That(result.Client, Is.Not.Null);
                Assert.That(result.Client.User, Is.Not.Null);
                Assert.That(result.Client.User.Name, Is.EqualTo("jdoe"));

                Assert.That(result.Agent, Is.Not.Null);
                Assert.That(result.Agent.Name, Is.EqualTo("MyApp"));
                Assert.That(result.Agent.Id, Is.EqualTo("app-1"));
                Assert.That(result.Agent.Version, Is.EqualTo("1.2.3"));

                Assert.That(result.Event, Is.Not.Null);
                Assert.That(result.Event.Id, Is.EqualTo("req-123"));

                Assert.That(result.Trace, Is.Not.Null);
                Assert.That(result.Trace.Id, Is.EqualTo("11111111-1111-1111-1111-111111111111"));

                Assert.That(result.Process, Is.Not.Null);
                Assert.That(result.Process.Pid, Is.EqualTo(42));
                Assert.That(result.Process.Name, Is.EqualTo("proc-name"));
                Assert.That(result.Process.Thread, Is.Not.Null);
                Assert.That(result.Process.Thread.Id, Is.EqualTo(7));
                Assert.That(result.Process.Thread.Name, Is.EqualTo("thread-1"));

                Assert.That(result.Host, Is.Not.Null);
                Assert.That(result.Host.Name, Is.EqualTo("MACHINE"));
            }
        }

        [Test]
        public void Map_WithException_PopulatesError()
        {
            // Arrange
            var timestamp = DateTimeOffset.UtcNow;
            var template = _parser.Parse("boom");
            var ex = new InvalidOperationException("something went wrong");
            var logEvent = new LogEvent(timestamp, LogEventLevel.Error, ex, template, new List<LogEventProperty>());
            var mapper = new SerilogEventToTradingEventMapper("MyApp");

            // Act
            var result = mapper.Map(logEvent);

            // Assert
            using (Assert.EnterMultipleScope())
            {
                Assert.That(result.Error, Is.Not.Null);
                Assert.That(result.Error.Message, Is.EqualTo("something went wrong"));
                Assert.That(result.Error.Type, Is.EqualTo("InvalidOperationException"));
                Assert.That(result.Error.Code, Is.EqualTo(ex.HResult.ToString()));
            }
        }
    }
}
