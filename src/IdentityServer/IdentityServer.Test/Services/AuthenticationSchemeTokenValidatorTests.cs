// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

using System.Security.Claims;
using Microsoft.AspNetCore.Authentication;
using Microsoft.AspNetCore.Http;
using NSubstitute;
using IdentityServer.Services;

namespace IdentityServer.Test.Services;

[TestFixture]
public class AuthenticationSchemeTokenValidatorTests
{
    private const string _schemeName = "TestScheme";
    private IServiceProvider _serviceProvider;
    private AuthenticationSchemeTokenValidator _validator;
    private IAuthenticationService _authService;

    [SetUp]
    public void SetUp()
    {
        _serviceProvider = Substitute.For<IServiceProvider>();
        _authService = Substitute.For<IAuthenticationService>();
        _serviceProvider.GetService(typeof(IAuthenticationService)).Returns(_authService);
        _validator = new AuthenticationSchemeTokenValidator(_schemeName, _serviceProvider);
    }

    [Test]
    public async Task ValidateAccessTokenAsync_WhenAuthenticationFails_ShouldReturnErrorResult()
    {
        var token = "invalid-token";
        var authResult = AuthenticateResult.Fail("fail reason");
        _authService.AuthenticateAsync(Arg.Any<HttpContext>(), _schemeName).Returns(Task.FromResult(authResult));

        var result = await _validator.ValidateAccessTokenAsync(token);

        using (Assert.EnterMultipleScope())
        {
            Assert.That(result.IsError, Is.True);
            Assert.That(result.Error, Is.EqualTo($"Authentication scheme {_schemeName} rejected the token"));
            Assert.That(result.ErrorDescription, Is.EqualTo("fail reason"));
        }
    }

    [Test]
    public async Task ValidateAccessTokenAsync_WhenAuthenticationSucceeds_ShouldReturnClaims()
    {
        var token = "valid-token";
        var claims = new[] { new Claim("type1", "value1"), new Claim("type2", "value2") };
        var principal = new ClaimsPrincipal(new ClaimsIdentity(claims));
        var authResult = AuthenticateResult.Success(new AuthenticationTicket(principal, _schemeName));
        _authService.AuthenticateAsync(Arg.Any<HttpContext>(), _schemeName).Returns(Task.FromResult(authResult));

        var result = await _validator.ValidateAccessTokenAsync(token);

        using (Assert.EnterMultipleScope())
        {
            Assert.That(result.IsError, Is.False);
            Assert.That(result.Claims.Count(), Is.EqualTo(2));
            Assert.That(result.Claims.Any(c => c.Type == "type1" && c.Value == "value1"), Is.True);
            Assert.That(result.Claims.Any(c => c.Type == "type2" && c.Value == "value2"), Is.True);
        }
    }

    [Test]
    public void ValidateIdentityTokenAsync_WhenCalled_ShouldThrowNotImplementedException()
    {
        Assert.That(() => _validator.ValidateIdentityTokenAsync("token"), Throws.TypeOf<NotImplementedException>());
    }
}
