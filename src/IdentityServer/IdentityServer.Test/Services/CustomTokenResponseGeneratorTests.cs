using Duende.IdentityServer;
using Duende.IdentityServer.ResponseHandling;
using Duende.IdentityServer.Services;
using Duende.IdentityServer.Stores;
using Duende.IdentityServer.Validation;
using Microsoft.Extensions.Logging;
using NSubstitute;
using IdentityServer.Services;

namespace IdentityServer.Test.Services;

[TestFixture]
public class CustomTokenResponseGeneratorTests
{
    private IClock _clock;
    private ITokenService _tokenService;
    private IRefreshTokenService _refreshTokenService;
    private IScopeParser _scopeParser;
    private IResourceStore _resourceStore;
    private IClientStore _clientStore;
    private ILogger<CustomTokenResponseGenerator> _logger;
    private CustomTokenResponseGenerator _generator;

    [SetUp]
    public void SetUp()
    {
        _clock = Substitute.For<IClock>();
        _tokenService = Substitute.For<ITokenService>();
        _refreshTokenService = Substitute.For<IRefreshTokenService>();
        _scopeParser = Substitute.For<IScopeParser>();
        _resourceStore = Substitute.For<IResourceStore>();
        _clientStore = Substitute.For<IClientStore>();
        _logger = Substitute.For<ILogger<CustomTokenResponseGenerator>>();
        _generator = new CustomTokenResponseGenerator(
            _clock, _tokenService, _refreshTokenService, _scopeParser, _resourceStore, _clientStore, _logger);
    }

    private sealed class TestableCustomTokenResponseGenerator : CustomTokenResponseGenerator
    {
        public TestableCustomTokenResponseGenerator(
            IClock clock,
            ITokenService tokenService,
            IRefreshTokenService refreshTokenService,
            IScopeParser scopeParser,
            IResourceStore resources,
            IClientStore clients,
            ILogger<CustomTokenResponseGenerator> logger)
            : base(clock, tokenService, refreshTokenService, scopeParser, resources, clients, logger) { }

        public new Task<TokenResponse> ProcessTokenRequestAsync(TokenRequestValidationResult validationResult)
            => base.ProcessTokenRequestAsync(validationResult);
    }

    private static ValidatedTokenRequest CreateValidatedTokenRequest()
    {
        return new ValidatedTokenRequest();
    }

    [Test]
    public void Constructor_WhenCalled_ShouldCreateInstance()
    {
        Assert.That(_generator, Is.Not.Null);
        Assert.That(_generator, Is.InstanceOf<CustomTokenResponseGenerator>());
    }

    [Test]
    public async Task ProcessTokenRequestAsync_WhenCustomResponseHasLifetime_ShouldSetAccessTokenLifetime()
    {
        var validatedRequest = CreateValidatedTokenRequest();
        var customResponse = new Dictionary<string, object>
        {
            { Abstraction.Constants.TokenExchange.AccessTokenLifetimeTemporaryClaimName, 1234 }
        };
        var validationResult = new TokenRequestValidationResult(validatedRequest, customResponse);
        var generator = new TestableCustomTokenResponseGenerator(
            _clock, _tokenService, _refreshTokenService, _scopeParser, _resourceStore, _clientStore, _logger);
        var result = await generator.ProcessTokenRequestAsync(validationResult);
        using (Assert.EnterMultipleScope())
        {
            Assert.That(validationResult.ValidatedRequest.AccessTokenLifetime, Is.EqualTo(1234));
            Assert.That(result, Is.Not.Null);
        }
    }

    [Test]
    public async Task ProcessTokenRequestAsync_WhenCustomResponseIsNull_ShouldNotSetAccessTokenLifetime()
    {
        var validatedRequest = CreateValidatedTokenRequest();
        var validationResult = new TokenRequestValidationResult(validatedRequest, null);
        var generator = new TestableCustomTokenResponseGenerator(
            _clock, _tokenService, _refreshTokenService, _scopeParser, _resourceStore, _clientStore, _logger);
        var result = await generator.ProcessTokenRequestAsync(validationResult);
        using (Assert.EnterMultipleScope())
        {
            Assert.That(validationResult.ValidatedRequest.AccessTokenLifetime, Is.Zero);
            Assert.That(result, Is.Not.Null);
        }
    }

    [Test]
    public async Task ProcessTokenRequestAsync_WhenCustomResponseHasNoLifetime_ShouldNotSetAccessTokenLifetime()
    {
        var validatedRequest = CreateValidatedTokenRequest();
        var customResponse = new Dictionary<string, object> { { "other", 999 } };
        var validationResult = new TokenRequestValidationResult(validatedRequest, customResponse);
        var generator = new TestableCustomTokenResponseGenerator(
            _clock, _tokenService, _refreshTokenService, _scopeParser, _resourceStore, _clientStore, _logger);
        var result = await generator.ProcessTokenRequestAsync(validationResult);
        using (Assert.EnterMultipleScope())
        {
            Assert.That(validationResult.ValidatedRequest.AccessTokenLifetime, Is.Zero);
            Assert.That(result, Is.Not.Null);
        }
    }
}
