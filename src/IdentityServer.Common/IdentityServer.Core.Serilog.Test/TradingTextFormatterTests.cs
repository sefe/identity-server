using NUnit.Framework;
using Serilog.Events;
using Serilog.Parsing;
using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using IdentityServer.Core.Serilog;

namespace IdentityServer.Core.Serilog.Test
{
    public class TradingTextFormatterTests
    {
        private const string _appName = "TestApp";
        private const string _defaultMessage = "Test message";
        private const string _errorMessage = "Error occurred";
        private const string _debugMessage = "Debug info";
        private static readonly MessageTemplateParser _parser = new();

        private TradingTextFormatter _sut;

        [SetUp]
        public void SetUp()
        {
            _sut = new TradingTextFormatter(_appName);
        }

        [Test]
        public void Format_WithStreamWriter_WritesSerializedLineAndNewline()
        {
            // Arrange
            var ev = CreateLogEvent(new[] { Scalar("SourceContext", "Logger"), Scalar("IdentityName", "user1") }, LogEventLevel.Information, _defaultMessage);

            // Act
            var output = FormatToStream(ev, _sut);

            // Assert
            using (Assert.EnterMultipleScope())
            {
                Assert.That(output, Is.Not.Empty);
                Assert.That(output.TrimEnd(), Does.EndWith("}"));
                Assert.That(output, Does.EndWith(Environment.NewLine));
                Assert.That(output, Does.Contain(_defaultMessage));
                Assert.That(output, Does.Contain("\"ecs\""));
            }
        }

        [Test]
        public void Format_WithStringWriter_WritesSerializedLine()
        {
            // Arrange
            var ev = CreateLogEvent(new[] { Scalar("SourceContext", "Logger"), Scalar("IdentityName", "user2") }, LogEventLevel.Information, _defaultMessage);

            // Act
            var output = FormatToString(ev, _sut);

            // Assert
            using (Assert.EnterMultipleScope())
            {
                Assert.That(output, Is.Not.Empty);
                Assert.That(output, Does.Contain(_defaultMessage));
                Assert.That(output, Does.Contain("\"ecs\""));
                Assert.That(output, Does.EndWith(Environment.NewLine));
            }
        }

        [Test]
        public void Format_WithExceptionEvent_OutputContainsErrorFields()
        {
            // Arrange
            var ex = new InvalidOperationException("boom failure");
            var ev = CreateLogEvent(new[] { Scalar("SourceContext", "Logger") }, LogEventLevel.Error, _errorMessage, ex);

            // Act
            var output = FormatToString(ev, _sut);

            // Assert
            using (Assert.EnterMultipleScope())
            {
                Assert.That(output, Does.Contain(_errorMessage));
                Assert.That(output, Does.Contain("boom failure"));
                Assert.That(output, Does.Contain("\"error\""));
                Assert.That(output, Does.Contain("\"type\""));
            }
        }

        [Test]
        public void Format_IfNoExceptionEvent_DoesNotContainErrorSection()
        {
            // Arrange
            var ev = CreateLogEvent(new[] { Scalar("SourceContext", "Logger") }, LogEventLevel.Information, _defaultMessage);

            // Act
            var output = FormatToString(ev, _sut);

            // Assert
            using (Assert.EnterMultipleScope())
            {
                Assert.That(output, Does.Not.Contain("\"error\""));
                Assert.That(output, Does.Not.Contain("\"stackTrace\""));
            }
        }

        [Test]
        public void Format_WithDebugEvent_OutputContainsMessageAndContext()
        {
            // Arrange
            var ev = CreateLogEvent(new[] { Scalar("SourceContext", "Logger.Core"), Scalar("IdentityName", "user4") }, LogEventLevel.Debug, _debugMessage);

            // Act
            var output = FormatToString(ev, _sut);

            // Assert
            using (Assert.EnterMultipleScope())
            {
                Assert.That(output, Does.Contain(_debugMessage));
                Assert.That(output, Does.Contain("\"ecs\""));
                Assert.That(output, Does.Contain("Logger.Core"));
                Assert.That(output, Does.Contain("user4"));
            }
        }

        [TestCase(LogEventLevel.Information, "Info msg")]
        [TestCase(LogEventLevel.Warning, "Warn msg")]
        [TestCase(LogEventLevel.Error, "Err msg")]
        public void Format_WithVariousLevels_IncludesMessage(LogEventLevel level, string msg)
        {
            // Arrange
            var ev = CreateLogEvent(new[] { Scalar("SourceContext", "Logger") }, level, msg);

            // Act
            var output = FormatToString(ev, _sut);

            // Assert
            using (Assert.EnterMultipleScope())
            {
                Assert.That(output, Does.Contain(msg));
                Assert.That(output, Does.Contain("\"ecs\""));
            }
        }

        private static LogEventProperty Scalar(string name, object value) => new(name, new ScalarValue(value));

        private static LogEvent CreateLogEvent(IEnumerable<LogEventProperty> properties, LogEventLevel level, string message, Exception? ex = null)
        {
            var template = _parser.Parse(message);
            return new LogEvent(DateTimeOffset.UtcNow, level, ex, template, properties.ToList());
        }

        private static string FormatToString(LogEvent logEvent, TradingTextFormatter formatter)
        {
            using var sw = new StringWriter();
            formatter.Format(logEvent, sw);
            return sw.ToString();
        }

        private static string FormatToStream(LogEvent logEvent, TradingTextFormatter formatter)
        {
            using var ms = new MemoryStream();
            using var writer = new StreamWriter(ms);
            formatter.Format(logEvent, writer);
            writer.Flush();
            ms.Position = 0;
            using var reader = new StreamReader(ms);
            return reader.ReadToEnd();
        }
    }
}
