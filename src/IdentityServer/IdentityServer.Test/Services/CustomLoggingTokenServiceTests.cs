// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

using System.Security.Claims;
using Duende.IdentityModel;
using Duende.IdentityServer;
using Duende.IdentityServer.Configuration;
using Duende.IdentityServer.Models;
using Duende.IdentityServer.Services;
using Duende.IdentityServer.Stores;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;
using NSubstitute;
using IdentityServer.Abstraction.Configs;
using IdentityServer.Services;

namespace IdentityServer.Test.Services;

[TestFixture]
public class CustomLoggingTokenServiceTests
{
    private IClock _clock;
    private IKeyMaterialService _keys;
    private IClaimsService _claimsProvider;
    private IReferenceTokenStore _referenceTokenStore;
    private ITokenCreationService _creationService;
    private TestLogger<CustomLoggingTokenService> _logger;
    private IOptions<IdentityServerOptions> _options;
    private IOptions<CustomTokenLoggingSettings> _loggingSettings;
    private CustomLoggingTokenService _service;

    [SetUp]
    public void SetUp()
    {
        _clock = Substitute.For<IClock>();
        _keys = Substitute.For<IKeyMaterialService>();
        _claimsProvider = Substitute.For<IClaimsService>();
        _referenceTokenStore = Substitute.For<IReferenceTokenStore>();
        _creationService = Substitute.For<ITokenCreationService>();
        _logger = new TestLogger<CustomLoggingTokenService>();
        _options = Substitute.For<IOptions<IdentityServerOptions>>();
        _options.Value.Returns(new IdentityServerOptions());

        // Default: log all safe JWT parts, 16 chars for reference tokens
        var settings = new CustomTokenLoggingSettings
        {
            EnableCustomTokenLogging = true,
            ReferenceTokenDefaultVisibleLength = 16,
            JwtTokenVisibleParts = JwtTokenVisibleParts.All
        };
        _loggingSettings = Options.Create(settings);

        _service = new CustomLoggingTokenService(
            _clock, _keys, _claimsProvider, _referenceTokenStore, _creationService, _logger, _options, _loggingSettings
        );
    }

    [Test]
    public async Task CreateSecurityTokenAsync_WithJwtAccessToken_LogsAndReturnsToken()
    {
        // Arrange
        var token = new Token(OidcConstants.TokenTypes.AccessToken)
        {
            ClientId = "client2",
            AccessTokenType = AccessTokenType.Jwt,
            Claims = new List<Claim>
                {
                    new("sub", "subject2"),
                    new("name", "Test User2"),
                    new("scope", "profile"),
                    new("scope", "api1.scope1")
                }
        };
        var rawToken = "header.payload.signature";
        _creationService.CreateTokenAsync(token).Returns(Task.FromResult(rawToken));

        // Act
        var result = await _service.CreateSecurityTokenAsync(token);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result, Is.EqualTo(rawToken));

            var lastLog = _logger.Logs[^1];
            Assert.That(lastLog.logLevel, Is.EqualTo(LogLevel.Information));
            Assert.That(lastLog.exc, Is.Null);
            Assert.That(lastLog.formattedString, Does.Contain("Issued token: Type=access_token")
                .And.Contain("ClientId=client2")
                .And.Contain("Scopes=profile, api1.scope1")
                .And.Contain("AccessTokenType=Jwt")
                .And.Contain("SubjectId=subject2")
                .And.Contain("Display Name=Test User2")
                .And.Contain("TokenPreview=header.payload"));
        }
    }

    [Test]
    public async Task CreateSecurityTokenAsync_WithReferenceAccessToken_LogsAndReturnsToken()
    {
        // Arrange
        var token = new Token(OidcConstants.TokenTypes.AccessToken)
        {
            ClientId = "client2",
            AccessTokenType = AccessTokenType.Reference,
            Claims = new List<Claim>
                {
                    new("sub", "subject2"),
                    new("name", "Test User2"),
                    new("scope", "profile"),
                    new("scope", "api1.scope1")
                }
        };
        var rawToken = "referenceTokenValue1234_5678901234567890";
        _referenceTokenStore.StoreReferenceTokenAsync(token).Returns(Task.FromResult(rawToken));

        // Act
        var result = await _service.CreateSecurityTokenAsync(token);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result, Is.EqualTo(rawToken));

            var (logLevel, exc, formattedString) = _logger.Logs[^1];
            Assert.That(logLevel, Is.EqualTo(LogLevel.Information));
            Assert.That(exc, Is.Null);
            Assert.That(formattedString, Does.Contain("Issued token: Type=access_token")
                .And.Contain("ClientId=client2")
                .And.Contain("Scopes=profile, api1.scope1")
                .And.Contain("AccessTokenType=Reference")
                .And.Contain("SubjectId=subject2")
                .And.Contain("Display Name=Test User2")
                .And.Contain("TokenPreview=***5678901234567890"));
        }
    }

    [Test]
    public async Task CreateSecurityTokenAsync_WithNoUserClaims_LogsAndReturnsToken()
    {
        // Arrange
        var token = new Token(OidcConstants.TokenTypes.AccessToken)
        {
            ClientId = "client2",
            AccessTokenType = AccessTokenType.Jwt
        };
        var rawToken = "header.payload.signature";
        _creationService.CreateTokenAsync(token).Returns(Task.FromResult(rawToken));

        // Act
        var result = await _service.CreateSecurityTokenAsync(token);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result, Is.EqualTo(rawToken));

            var (logLevel, exc, formattedString) = _logger.Logs[^1];
            Assert.That(logLevel, Is.EqualTo(LogLevel.Information));
            Assert.That(exc, Is.Null);
            Assert.That(formattedString, Does.Contain("Issued token: Type=access_token, AccessTokenType=Jwt, ClientId=client2, SubjectId=(null), Display Name=(null), Scopes=, TokenPreview=header.payload"));
        }
    }

    [Test]
    public async Task CreateSecurityTokenAsync_WithNonAccessToken_LogsAndReturnsToken()
    {
        // Arrange
        var token = new Token(OidcConstants.TokenTypes.IdentityToken)
        {
            ClientId = "client2",
            AccessTokenType = AccessTokenType.Jwt
        };
        var rawToken = "123456789";
        _creationService.CreateTokenAsync(token).Returns(Task.FromResult(rawToken));

        // Act
        var result = await _service.CreateSecurityTokenAsync(token);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result, Is.EqualTo(rawToken));

            var (logLevel, exc, formattedString) = _logger.Logs[^1];
            Assert.That(logLevel, Is.EqualTo(LogLevel.Information));
            Assert.That(exc, Is.Null);
            Assert.That(formattedString, Does.Contain("Issued token: Type=id_token")
                .And.Contain("ClientId=client2")
                .And.Contain("TokenPreview=***6789"));
        }
    }

    public class TestLogger<T> : ILogger<T>
    {
        public List<(LogLevel logLevel, Exception exc, string formattedString)> Logs { get; } = new();

        public IDisposable BeginScope<TState>(TState state) => null;

        public bool IsEnabled(LogLevel logLevel) => true;

        public void Log<TState>(
            LogLevel logLevel,
            EventId eventId,
            TState state,
            Exception exception,
            Func<TState, Exception, string> formatter)
        {
            Logs.Add((logLevel, exception, formatter(state, exception)));
        }
    }
}
