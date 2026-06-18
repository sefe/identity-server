using System.IdentityModel.Tokens.Jwt;
using Duende.IdentityServer.Validation;
using Microsoft.Extensions.Logging.Abstractions;
using NSubstitute;
using IdentityServer.Services;

namespace IdentityServer.Test.Services;

[TestFixture]
public class TokenValidatorSelectorTests
{
    private ITokenValidator _defaultValidator;
    private AuthSchemeIssuerMapping _authSchemeIssuerMapping;
    private IServiceProvider _serviceProvider;
    private TokenValidatorSelector _selector;

    [SetUp]
    public void SetUp()
    {
        _defaultValidator = Substitute.For<ITokenValidator>();
        _authSchemeIssuerMapping = new AuthSchemeIssuerMapping();
        _serviceProvider = Substitute.For<IServiceProvider>();
        _selector = new TokenValidatorSelector(_defaultValidator, _authSchemeIssuerMapping, NullLogger<TokenValidatorSelector>.Instance, _serviceProvider);
    }

    [Test]
    public void SelectValidator_WhenIssuerIsKnown_ShouldReturnAuthenticationSchemeTokenValidator()
    {
        // Arrange
        var issuer = "https://issuer.example.com";
        var scheme = "TestScheme";
        _authSchemeIssuerMapping.IssuerToSchemeMap.Add(issuer, scheme);
        var token = new JwtSecurityToken(issuer: issuer);
        var handler = new JwtSecurityTokenHandler();
        var jwt = handler.WriteToken(token);

        // Act
        var validator = _selector.SelectValidator(jwt);

        // Assert
        Assert.That(validator as AuthenticationSchemeTokenValidator, Is.Not.Null);
    }

    [Test]
    public void SelectValidator_WhenIssuerIsUnknown_ShouldReturnDefaultValidator()
    {
        // Arrange
        var issuer = "https://unknown-issuer.com";
        var token = new JwtSecurityToken(issuer: issuer);
        var handler = new JwtSecurityTokenHandler();
        var jwt = handler.WriteToken(token);

        // Act
        var validator = _selector.SelectValidator(jwt);

        // Assert
        Assert.That(validator, Is.EqualTo(_defaultValidator));
    }

    [Test]
    public void SelectValidator_WhenJwtIsInvalid_ShouldReturnDefaultValidator()
    {
        // Arrange
        var invalidToken = "not-a-jwt-token";

        // Act
        var validator = _selector.SelectValidator(invalidToken);

        // Assert
        Assert.That(validator, Is.EqualTo(_defaultValidator));
    }
}
