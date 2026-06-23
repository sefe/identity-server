// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

using System.Collections.Specialized;
using Duende.IdentityServer.Models;
using Duende.IdentityServer.Validation;
using Microsoft.Extensions.Options;
using NSubstitute;
using IdentityServer.Abstraction.Configs;
using IdentityServer.Services.Validation;
using IdentityServer.Tests.Common;

namespace IdentityServer.Test.Services.Validation;

[TestFixture]
public class CustomIntrospectionRequestValidatorTests
{
    private IIntrospectionRequestValidator _defaultValidator;
    private IOptions<CustomTokenLoggingSettings> _loggingSettings;
    private MockLogger<CustomIntrospectionRequestValidator> _logger;
    private CustomIntrospectionRequestValidator _sut;

    [SetUp]
    public void SetUp()
    {
        _defaultValidator = Substitute.For<IIntrospectionRequestValidator>();
        _logger = new MockLogger<CustomIntrospectionRequestValidator>();
        _loggingSettings = Options.Create(new CustomTokenLoggingSettings
        {
            ReferenceTokenDefaultVisibleLength = 4
        });
        _sut = new CustomIntrospectionRequestValidator(_defaultValidator, _loggingSettings, _logger);
    }

    [Test]
    public async Task ValidateAsync_ByApi_LogsApiId()
    {
        // Arrange
        var value = Guid.NewGuid().ToString() + "cdef";
        var context = new IntrospectionRequestValidationContext
        {
            Api = new ApiResource() { Name = "MyApi" },
            Parameters = new NameValueCollection { { "token", value } }
        };
        var expectedResult = new IntrospectionRequestValidationResult();
        _defaultValidator.ValidateAsync(context).Returns(Task.FromResult(expectedResult));

        // Act
        _ = await _sut.ValidateAsync(context);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(_logger.CapturedInfo, Has.Count.EqualTo(1));
            Assert.That(_logger.CapturedInfo[0], Does.Contain("API 'MyApi'"));
        }
    }

    [Test]
    public async Task ValidateAsync_ByApplication_LogsClientId()
    {
        // Arrange
        var value = "";
        var context = new IntrospectionRequestValidationContext
        {
            Client = new Client() { ClientId = "MyApp" },
            Parameters = new NameValueCollection { { "token", value } }
        };
        var expectedResult = new IntrospectionRequestValidationResult();
        _defaultValidator.ValidateAsync(context).Returns(Task.FromResult(expectedResult));

        // Act
        _ = await _sut.ValidateAsync(context);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(_logger.CapturedInfo, Has.Count.EqualTo(1));
            Assert.That(_logger.CapturedInfo[0], Does.Contain("Application 'MyApp'"));
        }
    }

    [Test]
    public async Task ValidateAsync_WithReferenceToken_LogsObfuscatedTokenAndReturnsResult()
    {
        // Arrange
        var value = Guid.NewGuid().ToString() + "cdef";
        var context = new IntrospectionRequestValidationContext
        {
            Parameters = new NameValueCollection { { "token", value } }
        };
        var expectedResult = new IntrospectionRequestValidationResult();
        _defaultValidator.ValidateAsync(context).Returns(Task.FromResult(expectedResult));

        // Act
        var result = await _sut.ValidateAsync(context);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result, Is.EqualTo(expectedResult));
            Assert.That(_logger.CapturedInfo, Has.Count.EqualTo(1));
            Assert.That(_logger.CapturedInfo[0], Does.Contain("TokenPreview=***cdef"));
        }
    }

    [Test]
    public async Task ValidateAsync_WithShortReferenceToken_LogsObfuscatedShortToken()
    {
        // Arrange
        var value = "1234";
        var context = new IntrospectionRequestValidationContext
        {
            Parameters = new NameValueCollection { { "token", value } }
        };
        var expectedResult = new IntrospectionRequestValidationResult();
        _defaultValidator.ValidateAsync(context).Returns(Task.FromResult(expectedResult));

        // Act
        var result = await _sut.ValidateAsync(context);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result, Is.EqualTo(expectedResult));
            Assert.That(_logger.CapturedInfo, Has.Count.EqualTo(1));
            Assert.That(_logger.CapturedInfo[0], Does.Contain("TokenPreview=***34"));
        }
    }

    [TestCase(null)]
    [TestCase("")]
    public async Task ValidateAsync_WithEmptyReferenceToken_LogsNoToken(string token)
    {
        // Arrange
        var context = new IntrospectionRequestValidationContext
        {
            Parameters = new NameValueCollection { { "token", token } }
        };
        var expectedResult = new IntrospectionRequestValidationResult();
        _defaultValidator.ValidateAsync(context).Returns(Task.FromResult(expectedResult));

        // Act
        var result = await _sut.ValidateAsync(context);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result, Is.EqualTo(expectedResult));
            Assert.That(_logger.CapturedInfo, Has.Count.EqualTo(1));
            Assert.That(_logger.CapturedInfo[0], Does.EndWith("TokenPreview="));
        }
    }

    [Test]
    public async Task ValidateAsync_WithNoReferenceToken_LogsNoToken()
    {
        // Arrange
        var context = new IntrospectionRequestValidationContext
        {
            Parameters = new NameValueCollection { }
        };
        var expectedResult = new IntrospectionRequestValidationResult();
        _defaultValidator.ValidateAsync(context).Returns(Task.FromResult(expectedResult));

        // Act
        var result = await _sut.ValidateAsync(context);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result, Is.EqualTo(expectedResult));
            Assert.That(_logger.CapturedInfo, Has.Count.EqualTo(1));
            Assert.That(_logger.CapturedInfo[0], Does.EndWith("TokenPreview="));
        }
    }
}
