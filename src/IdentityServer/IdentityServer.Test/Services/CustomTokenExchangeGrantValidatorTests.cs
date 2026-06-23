// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

using System.Security.Claims;
using Duende.IdentityModel;
using Duende.IdentityServer;
using Duende.IdentityServer.Models;
using Duende.IdentityServer.Validation;
using Microsoft.Extensions.Logging;
using NSubstitute;
using IdentityServer.Abstraction.Contracts;
using IdentityServer.Data.DuendeEntityExtensions;
using IdentityServer.Services;
using IdentityServer.Tests.Common.Builders;

namespace IdentityServer.Test.Services;

[TestFixture]
public class CustomTokenExchangeGrantValidatorTests
{
    private ITokenValidatorSelector _validatorSelector;
    private ISecretsListValidator _clientSecretValidator;
    private IStorage<ClientExt> _clientStorage;
    private ILogger<CustomTokenExchangeGrantValidator> _logger;
    private CustomTokenExchangeGrantValidator _validator;

    [SetUp]
    public void SetUp()
    {
        _validatorSelector = Substitute.For<ITokenValidatorSelector>();
        _clientSecretValidator = Substitute.For<ISecretsListValidator>();
        _clientStorage = Substitute.For<IStorage<ClientExt>>();
        _logger = Substitute.For<ILogger<CustomTokenExchangeGrantValidator>>();
        _validator = new CustomTokenExchangeGrantValidator(_validatorSelector, _clientSecretValidator, _clientStorage, _logger);
    }

    [Test]
    public void CreateCustomResponse_WhenCalled_ShouldReturnExpectedDictionary()
    {
        // Arrange
        var lifetime = 600;

        // Act
        var result = CustomTokenExchangeGrantValidator.CreateCustomResponse(lifetime);

        // Assert
        Assert.That(result, Contains.Key(OidcConstants.TokenResponse.IssuedTokenType));
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result[OidcConstants.TokenResponse.IssuedTokenType], Is.EqualTo(OidcConstants.TokenTypeIdentifiers.AccessToken));
            Assert.That(result, Contains.Key(Abstraction.Constants.TokenExchange.AccessTokenLifetimeTemporaryClaimName));
        }
        Assert.That(result[Abstraction.Constants.TokenExchange.AccessTokenLifetimeTemporaryClaimName], Is.EqualTo(lifetime));
    }

    [Test]
    public void ExtractAndValidateParameters_WhenValid_ShouldReturnSubjectToken()
    {
        // Arrange
        var context = CreateContextWithRaw(subjectToken: "token", subjectTokenType: Abstraction.Constants.TokenTypes.AccessToken);

        // Act
        var result = _validator.ExtractAndValidateParameters(context);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result, Is.EqualTo("token"));
            Assert.That(context.Result.ErrorDescription, Is.Null);
        }
    }

    [Test]
    public void ExtractAndValidateParameters_WhenSubjectTokenMissing_ShouldReturnEmptyAndSetError()
    {
        // Arrange
        var context = CreateContextWithRaw(subjectToken: null, subjectTokenType: Abstraction.Constants.TokenTypes.AccessToken);

        // Act
        var result = _validator.ExtractAndValidateParameters(context);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result, Is.Empty);
            Assert.That(context.Result.IsError, Is.True);
        }
    }

    [Test]
    public void ExtractAndValidateParameters_WhenSubjectTokenTypeInvalid_ShouldReturnEmptyAndSetError()
    {
        // Arrange
        var context = CreateContextWithRaw(subjectToken: "token", subjectTokenType: "invalid");

        // Act
        var result = _validator.ExtractAndValidateParameters(context);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result, Is.Empty);
            Assert.That(context.Result.IsError, Is.True);
        }
    }

    [Test]
    public async Task ValidateSubjectTokenAsync_WhenValid_ShouldReturnResult()
    {
        // Arrange
        var context = CreateContextWithRaw();
        var tokenValidator = Substitute.For<ITokenValidator>();
        var claims = new[] { new Claim(JwtClaimTypes.Email, "a@b.com") };
        tokenValidator.ValidateAccessTokenAsync(Arg.Any<string>())
            .Returns(Task.FromResult(new TokenValidationResult { Claims = claims, IsError = false }));
        _validatorSelector.SelectValidator(Arg.Any<string>()).Returns(tokenValidator);

        // Act
        var result = await _validator.ValidateSubjectTokenAsync("token", context);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result.Claims, Is.EquivalentTo(claims));
            Assert.That(context.Result.ErrorDescription, Is.Null);
        }
    }

    [Test]
    public async Task ValidateSubjectTokenAsync_WhenIsError_ShouldSetError()
    {
        // Arrange
        var context = CreateContextWithRaw();
        var tokenValidator = Substitute.For<ITokenValidator>();
        tokenValidator.ValidateAccessTokenAsync(Arg.Any<string>())
            .Returns(Task.FromResult(new TokenValidationResult { IsError = true, Error = "err" }));
        _validatorSelector.SelectValidator(Arg.Any<string>()).Returns(tokenValidator);

        // Act
        _ = await _validator.ValidateSubjectTokenAsync("token", context);

        // Assert
        Assert.That(context.Result.IsError, Is.True);
    }

    [Test]
    public async Task ValidateSubjectTokenAsync_WhenNoClaims_ShouldSetError()
    {
        // Arrange
        var context = CreateContextWithRaw();
        var tokenValidator = Substitute.For<ITokenValidator>();
        tokenValidator.ValidateAccessTokenAsync(Arg.Any<string>())
            .Returns(Task.FromResult(new TokenValidationResult { Claims = null }));
        _validatorSelector.SelectValidator(Arg.Any<string>()).Returns(tokenValidator);

        // Act
        _ = await _validator.ValidateSubjectTokenAsync("token", context);

        // Assert
        Assert.That(context.Result.IsError, Is.True);
    }

    [Test]
    public async Task ValidateIssuerSpecificClaims_WhenNoScopesForEntraIssuer_ShouldSetError()
    {
        // Arrange
        const string subjectClientId = "test-client-id";
        var context = CreateContextWithRaw();
        var claims = new List<Claim>
        {
            new(JwtClaimTypes.Issuer, "https://login.microsoftonline.com/tenantid")
        };
        var result = new TokenValidationResult { Claims = claims };

        // Act
        await _validator.ValidateIssuerSpecificClaims(result, context, subjectClientId);

        // Assert
        Assert.That(context.Result.IsError, Is.True);
    }

    [Test]
    public async Task ValidateIssuerSpecificClaims_WhenRequiredScopeMissingForEntraIssuer_ShouldSetError()
    {
        // Arrange
        const string subjectClientId = "test-client-id";
        var context = CreateContextWithRaw();
        var claims = new List<Claim>
        {
            new(JwtClaimTypes.Issuer, "https://sts.windows.net/tenantid"),
            new(Abstraction.Constants.ClaimNamesEntra.Scope, "other-scope")
        };
        var result = new TokenValidationResult { Claims = claims };

        // Act
        await _validator.ValidateIssuerSpecificClaims(result, context, subjectClientId);

        // Assert
        Assert.That(context.Result.IsError, Is.True);
    }

    [Test]
    public async Task ValidateIssuerSpecificClaims_WhenRequiredScopePresentForEntraIssuer_ShouldNotSetError()
    {
        // Arrange
        const string clientId = "test";
        const string subjectClientId = "test-client-id";
        var context = CreateContextWithRaw(clientId: clientId);
        var requiredScope = Abstraction.Constants.ScopeNamesEntra.IdentityServerTokenExchangeScope;
        var claims = new List<Claim>
        {
            new(JwtClaimTypes.Issuer, "https://login.microsoftonline.com/tenantid"),
            new(Abstraction.Constants.ClaimNamesEntra.Scope, $"other {requiredScope}")
        };
        var result = new TokenValidationResult { Claims = claims };
        var client = new ClientExtBuilder(clientId, "test").WithEntraApp(subjectClientId, "entra app").Build();
        SetupClientStorage_AnyAsync(client);

        // Act
        await _validator.ValidateIssuerSpecificClaims(result, context, subjectClientId);

        // Assert
        Assert.That(context.Result.ErrorDescription, Is.Null);
    }

    [Test]
    public async Task ValidateIssuerSpecificClaims_WhenSubjectTokenIssuerIsUnrecognized_ShouldSetError()
    {
        // Arrange
        const string subjectClientId = "test-client-id";
        var context = CreateContextWithRaw();
        context.Request.ClientId = "client123";
        var claims = new List<Claim>
        {
            new(JwtClaimTypes.Issuer, "https://something"),
            new(JwtClaimTypes.Audience, "client123")
        };
        var result = new TokenValidationResult { Claims = claims };

        // Act
        await _validator.ValidateIssuerSpecificClaims(result, context, subjectClientId);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(context.Result.IsError, Is.True);
            Assert.That(context.Result.Error, Is.EqualTo("invalid_request"));
            Assert.That(context.Result.ErrorDescription, Does.Contain("Unrecognized subject_token issuer"));
        }
    }

    [Test]
    public async Task ValidateIssuerSpecificClaims_WhenIdentityServerIssuerAudienceMissing_ShouldSetError()
    {
        // Arrange
        const string subjectClientId = "test-client-id";
        var context = CreateContextWithRaw();
        var claims = new List<Claim>
        {
            new(JwtClaimTypes.Issuer, "https://identityserver")
            // No audience claim
        };
        var result = new TokenValidationResult { Claims = claims };

        // Act
        await _validator.ValidateIssuerSpecificClaims(result, context, subjectClientId);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(context.Result.IsError, Is.True);
            Assert.That(context.Result.Error, Is.EqualTo("invalid_request"));
            Assert.That(context.Result.ErrorDescription, Is.EqualTo("subject_token issued by IdentityServer contains no audience claim"));
        }
    }

    [Test]
    public async Task ValidateIssuerSpecificClaims_WhenIdentityServerIssuerAudienceEqualsClientId_ShouldNotSetError()
    {
        // Arrange
        const string subjectClientId = "test-client-id";
        var context = CreateContextWithRaw();
        context.Request.ClientId = "client123";
        context.Request.Client = new Client { ClientId = context.Request.ClientId };
        var claims = new List<Claim>
        {
            new(JwtClaimTypes.Issuer, "https://identityserver"),
            new(JwtClaimTypes.Audience, "client123")
        };
        var result = new TokenValidationResult { Claims = claims };

        // Act
        await _validator.ValidateIssuerSpecificClaims(result, context, subjectClientId);

        // Assert
        Assert.That(context.Result.ErrorDescription, Is.Null);
    }

    [Test]
    public async Task ValidateIssuerSpecificClaims_WhenIdentityServerIssuerAudienceNotEqualsClientId_ShouldSetError()
    {
        // Arrange
        const string subjectClientId = "test-client-id";
        var context = CreateContextWithRaw();
        context.Request.ClientId = "client123";
        context.Request.Client = new Client { ClientId = context.Request.ClientId };
        var claims = new List<Claim>
        {
            new(JwtClaimTypes.Issuer, "https://identityserver"),
            new(JwtClaimTypes.Audience, "other-client")
        };
        var result = new TokenValidationResult { Claims = claims };

        // Act
        await _validator.ValidateIssuerSpecificClaims(result, context, subjectClientId);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(context.Result.IsError, Is.True);
            Assert.That(context.Result.Error, Is.EqualTo("invalid_client"));
            Assert.That(context.Result.ErrorDescription, Does.Contain("Client Id in the token request"));
        }
    }

    [Test]
    public void ExtractUserObjectIds_WhenPresent_ShouldReturnId()
    {
        // Arrange
        var context = CreateContextWithRaw();
        var claims = new[] { new Claim(Abstraction.Constants.ClaimNames.UserObjectId, "id") };
        var result = new TokenValidationResult { Claims = claims };

        // Act
        var userId = _validator.ExtractUserObjectIds(result, context);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(userId, Is.EqualTo("id"));
            Assert.That(context.Result.ErrorDescription, Is.Null);
        }
    }

    [Test]
    public void ExtractUserObjectIds_WhenMissing_ShouldSetErrorAndReturnEmpty()
    {
        // Arrange
        var context = CreateContextWithRaw();
        var claims = new[] { new Claim("other", "val") };
        var result = new TokenValidationResult { Claims = claims };

        // Act
        var userId = _validator.ExtractUserObjectIds(result, context);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(userId, Is.Empty);
            Assert.That(context.Result.IsError, Is.True);
        }
    }

    [Test]
    public void ExtractClientIds_WhenPresent_ShouldReturnId()
    {
        // Arrange
        var context = CreateContextWithRaw();
        var claims = new[] { new Claim(JwtClaimTypes.ClientId, "cid") };
        var result = new TokenValidationResult { Claims = claims };

        // Act
        var clientId = _validator.ExtractClientIds(result, context);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(clientId, Is.EqualTo("cid"));
            Assert.That(context.Result.ErrorDescription, Is.Null);
        }
    }

    [Test]
    public void ExtractClientIds_WhenMissing_ShouldSetErrorAndReturnEmpty()
    {
        // Arrange
        var context = CreateContextWithRaw();
        var claims = new[] { new Claim("other", "val") };
        var result = new TokenValidationResult { Claims = claims };

        // Act
        var clientId = _validator.ExtractClientIds(result, context);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(clientId, Is.Empty);
            Assert.That(context.Result.IsError, Is.True);
        }
    }

    [Test]
    public void BuildClaims_WhenCalled_ShouldReturnExpectedClaims()
    {
        // Arrange
        var context = CreateContextWithRaw();
        context.Request.Client = new Client { ClientId = "cid" };
        var claims = new[]
        {
            new Claim(JwtClaimTypes.Email, "a@b.com"),
            new Claim(JwtClaimTypes.Name, "name"),
            new Claim("other", "val")
        };
        var result = new TokenValidationResult { Claims = claims };

        // Act
        var builtClaims = _validator.BuildClaims(result);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(builtClaims.Any(c => c.Type == JwtClaimTypes.Email));
            Assert.That(builtClaims.Any(c => c.Type == JwtClaimTypes.Name));
            Assert.That(builtClaims.All(c => c.Type != "other" || c.Type == JwtClaimTypes.Actor));
        }
    }

    [Test]
    public void BuildActorClaim_WhenPreviousActorClaimPresent_ShouldPreservePreviousActorClaim()
    {
        // Arrange: previous actor claim as JSON
        var previousActor = new { ClientId = "prev-client", Extra = "data" };
        var prevActorJson = System.Text.Json.JsonSerializer.Serialize(new Dictionary<string, object>
        {
            { "client_id", previousActor.ClientId },
            { "Extra", previousActor.Extra }
        });
        var actorClaim = new Claim(JwtClaimTypes.Actor, prevActorJson, IdentityServerConstants.ClaimValueTypes.Json);
        var claims = new[]
        {
            actorClaim,
            new Claim(JwtClaimTypes.Email, "user@domain.com"),
            new Claim(JwtClaimTypes.Name, "User Name")
        };
        var validationResult = new TokenValidationResult { Claims = claims };
        var context = CreateContextWithRaw();
        context.Request.Client = new Client { ClientId = "new-client" };

        // Act
        var actorClaimResult = _validator.BuildActorClaim(validationResult, context);

        // Assert: The new Actor claim should contain the previous actor data nested under 'Act'
        Assert.That(actorClaimResult, Is.Not.Null);
        var actorObj = System.Text.Json.JsonSerializer.Deserialize<Dictionary<string, object>>(actorClaimResult.Value);
        Assert.That(actorObj, Contains.Key("client_id"));
        using (Assert.EnterMultipleScope())
        {
            Assert.That(actorObj["client_id"].ToString(), Is.EqualTo("new-client"));
            Assert.That(actorObj, Contains.Key("act"));
        }
        var actObj = System.Text.Json.JsonSerializer.Deserialize<Dictionary<string, object>>(actorObj["act"].ToString());
        Assert.That(actObj, Contains.Key("client_id"));
        using (Assert.EnterMultipleScope())
        {
            Assert.That(actObj["client_id"].ToString(), Is.EqualTo("prev-client"));
            Assert.That(actObj, Contains.Key("Extra"));
        }
        Assert.That(actObj["Extra"].ToString(), Is.EqualTo("data"));
    }

    [Test]
    public async Task ValidateAsync_WhenNoClientSecretAndNoActorToken_ShouldDemandClientAuthentication()
    {
        // Arrange
        var subjectToken = "valid-token";
        var userObjectId = "user-123";
        var clientId = "client-456";
        var requiredScope = Abstraction.Constants.ScopeNamesEntra.IdentityServerTokenExchangeScope;
        var plannedLifetime = 300; // 5 minutes in seconds
        var plannedExpirationTime = DateTimeOffset.Now.AddSeconds(plannedLifetime).ToUnixTimeSeconds();
        var claims = new[]
        {
            new Claim(Abstraction.Constants.ClaimNames.UserObjectId, userObjectId),
            new Claim(JwtClaimTypes.ClientId, clientId),
            new Claim(Abstraction.Constants.ClaimNamesEntra.Scope, $"other {requiredScope}"),
            new Claim(JwtClaimTypes.Email, "a@b.com"),
            new Claim(JwtClaimTypes.Name, "Test User"),
            new Claim(JwtClaimTypes.Expiration, plannedExpirationTime.ToString())
        };
        var tokenValidationResult = new TokenValidationResult { Claims = claims, IsError = false };
        var tokenValidator = Substitute.For<ITokenValidator>();
        tokenValidator.ValidateAccessTokenAsync(subjectToken)
            .Returns(Task.FromResult(tokenValidationResult));
        _validatorSelector.SelectValidator(subjectToken).Returns(tokenValidator);

        var context = new ExtensionGrantValidationContext
        {
            Request = new ValidatedTokenRequest
            {
                Raw = new System.Collections.Specialized.NameValueCollection
                {
                    { Abstraction.Constants.TokenExchange.SubjectToken, subjectToken },
                    { Abstraction.Constants.TokenExchange.SubjectTokenType, Abstraction.Constants.TokenTypes.AccessToken }
                },
                Client = new Client { ClientId = clientId },
                Secret = new ParsedSecret { Type = IdentityServerConstants.ParsedSecretTypes.NoSecret }
            }
        };

        // Act
        await _validator.ValidateAsync(context);

        // Assert
        Assert.That(context.Result, Is.Not.Null);
        using (Assert.EnterMultipleScope())
        {
            Assert.That(context.Result.IsError, Is.True, "Result should be error");
            Assert.That(context.Result.ErrorDescription, Is.Not.Null);
        }
    }

    [Test]
    public async Task ValidateAsync_WhenEndToEndSuccessfulFlow_ShouldSetExpectedGrantValidationResult()
    {
        // Arrange
        var subjectToken = "valid-token";
        var userObjectId = "user-123";
        var originalClientId = "client-123"; // the client which has received the subject token
        var clientId = "client-456";
        var requiredScope = Abstraction.Constants.ScopeNamesEntra.IdentityServerTokenExchangeScope;
        var plannedLifetime = 300; // 5 minutes in seconds
        var plannedExpirationTime = DateTimeOffset.Now.AddSeconds(plannedLifetime).ToUnixTimeSeconds();
        var claims = new[]
        {
            new Claim(JwtClaimTypes.Issuer, "https://identityserver"),
            new Claim(Abstraction.Constants.ClaimNames.UserObjectId, userObjectId),
            new Claim(JwtClaimTypes.Audience, clientId),
            new Claim(JwtClaimTypes.ClientId, originalClientId),
            new Claim(Abstraction.Constants.ClaimNamesEntra.Scope, $"other {requiredScope}"),
            new Claim(JwtClaimTypes.Email, "a@b.com"),
            new Claim(JwtClaimTypes.Name, "Test User"),
            new Claim(JwtClaimTypes.Expiration, plannedExpirationTime.ToString())
        };
        var tokenValidationResult = new TokenValidationResult { Claims = claims, IsError = false };
        var tokenValidator = Substitute.For<ITokenValidator>();
        tokenValidator.ValidateAccessTokenAsync(subjectToken)
            .Returns(Task.FromResult(tokenValidationResult));
        _validatorSelector.SelectValidator(subjectToken).Returns(tokenValidator);

        var context = new ExtensionGrantValidationContext
        {
            Request = new ValidatedTokenRequest
            {
                Raw = new System.Collections.Specialized.NameValueCollection
                {
                    { Abstraction.Constants.TokenExchange.SubjectToken, subjectToken },
                    { Abstraction.Constants.TokenExchange.SubjectTokenType, Abstraction.Constants.TokenTypes.AccessToken }
                },
                Client = new Client { ClientId = clientId },
                Secret = new ParsedSecret { Type = IdentityServerConstants.ParsedSecretTypes.SharedSecret }
            }
        };
        _clientSecretValidator.ValidateAsync(context.Request.Client.ClientSecrets, context.Request.Secret)
            .Returns(Task.FromResult(new SecretValidationResult { Success = true }));

        // Act
        await _validator.ValidateAsync(context);

        // Assert
        Assert.That(context.Result, Is.Not.Null);
        using (Assert.EnterMultipleScope())
        {
            Assert.That(context.Result.IsError, Is.False, "Result should not be error");
            Assert.That(context.Result.ErrorDescription, Is.Null);
            Assert.That(context.Result.Subject, Is.Not.Null);
            Assert.That(context.Result.CustomResponse, Is.Not.Null);
        }
        using (Assert.EnterMultipleScope())
        {
            Assert.That(context.Result.CustomResponse[OidcConstants.TokenResponse.IssuedTokenType], Is.EqualTo(OidcConstants.TokenTypeIdentifiers.AccessToken));
            Assert.That((int)context.Result.CustomResponse[Abstraction.Constants.TokenExchange.AccessTokenLifetimeTemporaryClaimName], Is.LessThanOrEqualTo(plannedLifetime));
        }
    }

    [Test]
    [TestCase("https://login.microsoftonline.com/tenantid", true)]
    [TestCase("https://sts.windows.net/tenantid", true)]
    [TestCase("https://otherissuer.com/tenantid", false)]
    [TestCase("http://login.microsoftonline.com/tenantid", false)]
    public void IsEntraIdIssuer_ForVariousIssuers_ShouldReturnExpectedResult(string issuer, bool expected)
    {
        // Arrange
        // Act
        var result = CustomTokenExchangeGrantValidator.IsEntraIdIssuer(issuer);

        // Assert
        Assert.That(result, Is.EqualTo(expected));
    }

    [Test]
    [TestCase("https://identityserver", true)]
    [TestCase("https://identityserver.example.com", true)]
    [TestCase("https://identityserver2", true)]
    [TestCase("https://identityserver/", true)]
    [TestCase("https://otherissuer.com", false)]
    [TestCase("http://identityserver", false)]
    public void IsIdentityServerIssuer_ForVariousIssuers_ShouldReturnExpectedResult(string issuer, bool expected)
    {
        // Arrange
        // Act
        var result = CustomTokenExchangeGrantValidator.IsIdentityServerIssuer(issuer);

        // Assert
        Assert.That(result, Is.EqualTo(expected));
    }

    [Test]
    public void ExtractAndValidateActorTokenParameters_WhenNoActorToken_ShouldReturnEmptyAndNotSetError()
    {
        // Arrange
        var context = CreateContextWithActorRaw(actorToken: null, actorTokenType: Abstraction.Constants.TokenTypes.AccessToken);

        // Act
        var result = _validator.ExtractAndValidateActorTokenParameters(context);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result, Is.Empty);
            Assert.That(context.Result.ErrorDescription, Is.Null);
        }
    }

    [Test]
    public void ExtractAndValidateActorTokenParameters_WhenActorTokenTypeInvalid_ShouldReturnEmptyAndSetError()
    {
        // Arrange
        var context = CreateContextWithActorRaw(actorToken: "actor-token", actorTokenType: "invalid");

        // Act
        var result = _validator.ExtractAndValidateActorTokenParameters(context);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result, Is.Empty);
            Assert.That(context.Result.IsError, Is.True);
        }
    }

    [Test]
    public void ExtractAndValidateActorTokenParameters_WhenActorTokenTooLong_ShouldReturnEmptyAndSetError()
    {
        // Arrange
        var longToken = new string('a', Abstraction.Constants.TokenExchange.MaxActorTokenLength + 1);
        var context = CreateContextWithActorRaw(actorToken: longToken, actorTokenType: Abstraction.Constants.TokenTypes.AccessToken);

        // Act
        var result = _validator.ExtractAndValidateActorTokenParameters(context);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result, Is.Empty);
            Assert.That(context.Result.IsError, Is.True);
        }
    }

    [Test]
    public void ExtractAndValidateActorTokenParameters_WhenValid_ShouldReturnActorToken()
    {
        // Arrange
        var context = CreateContextWithActorRaw(actorToken: "actor-token", actorTokenType: Abstraction.Constants.TokenTypes.AccessToken);

        // Act
        var result = _validator.ExtractAndValidateActorTokenParameters(context);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result, Is.EqualTo("actor-token"));
            Assert.That(context.Result.ErrorDescription, Is.Null);
        }
    }

    [Test]
    public async Task ValidateActorTokenAsync_WhenValid_ShouldReturnResult()
    {
        // Arrange
        var context = CreateContextWithActorRaw(actorToken: "actor-token", actorTokenType: Abstraction.Constants.TokenTypes.AccessToken);
        var tokenValidator = Substitute.For<ITokenValidator>();
        var claims = new[] { new Claim(JwtClaimTypes.Email, "actor@b.com") };
        tokenValidator.ValidateAccessTokenAsync(Arg.Any<string>())
            .Returns(Task.FromResult(new TokenValidationResult { Claims = claims, IsError = false }));
        _validatorSelector.SelectValidator(Arg.Any<string>()).Returns(tokenValidator);

        // Act
        var result = await _validator.ValidateActorTokenAsync("actor-token", context);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result.Claims, Is.EquivalentTo(claims));
            Assert.That(context.Result.ErrorDescription, Is.Null);
        }
    }

    [Test]
    public async Task ValidateActorTokenAsync_WhenIsError_ShouldSetErrorAndReturnNull()
    {
        // Arrange
        var context = CreateContextWithActorRaw(actorToken: "actor-token", actorTokenType: Abstraction.Constants.TokenTypes.AccessToken);
        var tokenValidator = Substitute.For<ITokenValidator>();
        tokenValidator.ValidateAccessTokenAsync(Arg.Any<string>())
            .Returns(Task.FromResult(new TokenValidationResult { IsError = true, Error = "err" }));
        _validatorSelector.SelectValidator(Arg.Any<string>()).Returns(tokenValidator);

        // Act
        var result = await _validator.ValidateActorTokenAsync("actor-token", context);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result, Is.Null);
            Assert.That(context.Result.IsError, Is.True);
        }
    }

    [Test]
    public async Task ValidateActorTokenAsync_WhenNoClaims_ShouldSetErrorAndReturnNull()
    {
        // Arrange
        var context = CreateContextWithActorRaw(actorToken: "actor-token", actorTokenType: Abstraction.Constants.TokenTypes.AccessToken);
        var tokenValidator = Substitute.For<ITokenValidator>();
        tokenValidator.ValidateAccessTokenAsync(Arg.Any<string>())
            .Returns(Task.FromResult(new TokenValidationResult { Claims = null }));
        _validatorSelector.SelectValidator(Arg.Any<string>()).Returns(tokenValidator);

        // Act
        var result = await _validator.ValidateActorTokenAsync("actor-token", context);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result, Is.Null);
            Assert.That(context.Result.IsError, Is.True);
        }
    }

    [Test]
    public void CalculateAccessTokenLifetime_WhenExpired_ShouldReturnZeroAndSetError()
    {
        // Arrange
        var context = CreateContextWithRaw();
        var expiredTime = DateTimeOffset.UtcNow.AddSeconds(-10).ToUnixTimeSeconds();
        var claims = new[] { new Claim(JwtClaimTypes.Expiration, expiredTime.ToString()) };
        var result = new TokenValidationResult { Claims = claims };

        // Act
        var lifetime = _validator.CalculateAccessTokenLifetime(result, context);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(lifetime, Is.Zero);
            Assert.That(context.Result.IsError, Is.True);
        }
    }

    [Test]
    public void CalculateAccessTokenLifetime_WhenOverMax_ShouldCapLifetime()
    {
        // Arrange
        var context = CreateContextWithRaw();
        var overMax = DateTimeOffset.UtcNow.AddSeconds(Abstraction.Constants.TokenExchange.MaxAccessTokenLifetimeSeconds + 1000).ToUnixTimeSeconds();
        var claims = new[] { new Claim(JwtClaimTypes.Expiration, overMax.ToString()) };
        var result = new TokenValidationResult { Claims = claims };

        // Act
        var lifetime = _validator.CalculateAccessTokenLifetime(result, context);

        // Assert
        Assert.That(lifetime, Is.EqualTo(Abstraction.Constants.TokenExchange.MaxAccessTokenLifetimeSeconds));
    }

    [Test]
    public void CalculateAccessTokenLifetime_WhenInRange_ShouldReturnValidLifetime()
    {
        // Arrange
        var context = CreateContextWithRaw();
        var valid = DateTimeOffset.UtcNow.AddSeconds(100).ToUnixTimeSeconds();
        var claims = new[] { new Claim(JwtClaimTypes.Expiration, valid.ToString()) };
        var result = new TokenValidationResult { Claims = claims };

        // Act
        var lifetime = _validator.CalculateAccessTokenLifetime(result, context);

        // Assert
        Assert.That(lifetime, Is.InRange(1, 100));
    }

    [Test]
    public void CalculateAccessTokenLifetime_WhenMissingExpiration_ShouldReturnZeroAndSetError()
    {
        // Arrange
        var context = CreateContextWithRaw();
        var claims = new[] { new Claim(JwtClaimTypes.Email, "a@b.com") };
        var result = new TokenValidationResult { Claims = claims };

        // Act
        var lifetime = _validator.CalculateAccessTokenLifetime(result, context);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(lifetime, Is.Zero);
            Assert.That(context.Result.IsError, Is.True);
        }
    }

    [Test]
    public void ExtractExpiresDateTime_WhenMissingExpiration_ShouldReturnMinAndSetError()
    {
        // Arrange
        var context = CreateContextWithRaw();
        var claims = new[] { new Claim(JwtClaimTypes.Email, "a@b.com") };
        var result = new TokenValidationResult { Claims = claims };

        // Act
        var dt = _validator.ExtractExpiresDateTime(result, context);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(dt, Is.EqualTo(DateTime.MinValue));
            Assert.That(context.Result.IsError, Is.True);
        }
    }

    [Test]
    public void ExtractExpiresDateTime_WhenExpirationInvalid_ShouldReturnMinAndSetError()
    {
        // Arrange
        var context = CreateContextWithRaw();
        var claims = new[] { new Claim(JwtClaimTypes.Expiration, "notanumber") };
        var result = new TokenValidationResult { Claims = claims };

        // Act
        var dt = _validator.ExtractExpiresDateTime(result, context);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(dt, Is.EqualTo(DateTime.MinValue));
            Assert.That(context.Result.IsError, Is.True);
        }
    }

    [Test]
    public void ExtractAuthDateTime_WhenMissingClaim_ShouldReturnNow()
    {
        // Arrange
        var claims = new[] { new Claim(JwtClaimTypes.Email, "a@b.com") };
        var result = new TokenValidationResult { Claims = claims };

        // Act
        var dt = CustomTokenExchangeGrantValidator.ExtractAuthDateTime(result);

        // Assert
        Assert.That(dt, Is.EqualTo(DateTime.UtcNow).Within(TimeSpan.FromSeconds(2)));
    }

    [Test]
    public void ExtractAuthDateTime_WhenValidClaim_ShouldReturnValue()
    {
        // Arrange
        var now = DateTimeOffset.UtcNow.ToUnixTimeSeconds();
        var claims = new[] { new Claim(JwtClaimTypes.AuthenticationTime, now.ToString()) };
        var result = new TokenValidationResult { Claims = claims };

        // Act
        var dt = CustomTokenExchangeGrantValidator.ExtractAuthDateTime(result);

        // Assert
        Assert.That(dt, Is.EqualTo(DateTimeOffset.FromUnixTimeSeconds(now).UtcDateTime));
    }

    [Test]
    public void BuildActorClaim_WhenNoPreviousActor_ShouldReturnClaim()
    {
        // Arrange
        var context = CreateContextWithRaw();
        context.Request.Client = new Client { ClientId = "cid" };
        var claims = new[] { new Claim(JwtClaimTypes.Email, "a@b.com") };
        var result = new TokenValidationResult { Claims = claims };

        // Act
        var actorClaim = _validator.BuildActorClaim(result, context);
        var actorObj = System.Text.Json.JsonSerializer.Deserialize<Dictionary<string, object>>(actorClaim.Value);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(actorObj[JwtClaimTypes.ClientId].ToString(), Is.EqualTo("cid"));
            Assert.That(actorObj.ContainsKey(JwtClaimTypes.Actor), Is.False);
        }
    }

    [Test]
    public void BuildActorClaim_WhenPreviousActor_ShouldReturnClaimWithPreviousActor()
    {
        // Arrange
        var context = CreateContextWithRaw();
        context.Request.Client = new Client { ClientId = "cid" };
        var prevActorJson = System.Text.Json.JsonSerializer.Serialize(new Dictionary<string, object> { { "client_id", "prev" } });
        var claims = new[] { new Claim(JwtClaimTypes.Actor, prevActorJson) };
        var result = new TokenValidationResult { Claims = claims };

        // Act
        var actorClaim = _validator.BuildActorClaim(result, context);
        var actorObj = System.Text.Json.JsonSerializer.Deserialize<Dictionary<string, object>>(actorClaim.Value);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(actorObj[JwtClaimTypes.ClientId].ToString(), Is.EqualTo("cid"));
            Assert.That(actorObj.ContainsKey(JwtClaimTypes.Actor), Is.True);
        }
    }

    [Test]
    public void BuildActorClaim_WhenInvalidPreviousActorJson_ShouldHandleGracefully()
    {
        // Arrange
        var context = CreateContextWithRaw();
        context.Request.Client = new Client { ClientId = "cid" };
        var claims = new[] { new Claim(JwtClaimTypes.Actor, "notjson") };
        var result = new TokenValidationResult { Claims = claims };

        // Act
        var actorClaim = _validator.BuildActorClaim(result, context);
        var actorObj = System.Text.Json.JsonSerializer.Deserialize<Dictionary<string, object>>(actorClaim.Value);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(actorObj[JwtClaimTypes.ClientId].ToString(), Is.EqualTo("cid"));
            Assert.That(actorObj.ContainsKey(JwtClaimTypes.Actor), Is.False);
        }
    }

    [Test]
    public async Task ValidateAsync_WhenNoClientSecretAndActorTokenPresent_ShouldSucceedWithActorToken()
    {
        // Arrange
        var subjectToken = "valid-token";
        var userObjectId = "user-actor";
        var originalClientId = "original-client";
        var clientId = "client-actor";
        var client = new ClientExtBuilder(clientId, "test").WithEntraApp(originalClientId, "entra app").Build();
        SetupClientStorage_AnyAsync(client);
        var requiredScope = Abstraction.Constants.ScopeNamesEntra.IdentityServerTokenExchangeScope;
        var plannedLifetime = 300; // 5 minutes in seconds
        var plannedExpirationTime = DateTimeOffset.Now.AddSeconds(plannedLifetime).ToUnixTimeSeconds();
        var claims = new[]
        {
            new Claim(Abstraction.Constants.ClaimNames.UserObjectId, userObjectId),
            new Claim(JwtClaimTypes.Issuer, "https://login.microsoftonline.com/123"),
            new Claim(JwtClaimTypes.Audience, clientId),
            new Claim(JwtClaimTypes.ClientId, originalClientId),
            new Claim(Abstraction.Constants.ClaimNamesEntra.Scope, $"other {requiredScope}"),
            new Claim(JwtClaimTypes.Email, "actor@b.com"),
            new Claim(JwtClaimTypes.Name, "Actor User"),
            new Claim(JwtClaimTypes.Expiration, plannedExpirationTime.ToString())
        };
        var tokenValidationResult = new TokenValidationResult { Claims = claims, IsError = false };
        var tokenValidator = Substitute.For<ITokenValidator>();
        tokenValidator.ValidateAccessTokenAsync(subjectToken)
            .Returns(Task.FromResult(tokenValidationResult));
        _validatorSelector.SelectValidator(subjectToken).Returns(tokenValidator);

        // Setup actor token
        var actorToken = "actor-token";
        var actorClaims = new[]
        {
            new Claim(JwtClaimTypes.ClientId, clientId), // same as in token request
            new Claim(JwtClaimTypes.Email, "actor@b.com"),
            new Claim(JwtClaimTypes.Name, "Actor User")
        };
        var actorValidationResult = new TokenValidationResult { Claims = actorClaims, IsError = false };
        var actorValidator = Substitute.For<ITokenValidator>();
        actorValidator.ValidateAccessTokenAsync(actorToken)
            .Returns(Task.FromResult(actorValidationResult));
        _validatorSelector.SelectValidator(actorToken).Returns(actorValidator);

        var context = new ExtensionGrantValidationContext
        {
            Request = new ValidatedTokenRequest
            {
                Raw = new System.Collections.Specialized.NameValueCollection
                {
                    { Abstraction.Constants.TokenExchange.SubjectToken, subjectToken },
                    { Abstraction.Constants.TokenExchange.SubjectTokenType, Abstraction.Constants.TokenTypes.AccessToken },
                    { Abstraction.Constants.TokenExchange.ActorToken, actorToken },
                    { Abstraction.Constants.TokenExchange.ActorTokenType, Abstraction.Constants.TokenTypes.AccessToken }
                },
                Client = new Client { ClientId = clientId },
                Secret = new ParsedSecret { Type = IdentityServerConstants.ParsedSecretTypes.NoSecret }
            }
        };

        // Act
        await _validator.ValidateAsync(context);

        // Assert
        Assert.That(context.Result, Is.Not.Null);
        using (Assert.EnterMultipleScope())
        {
            Assert.That(context.Result.IsError, Is.False, "Result should not be error");
            Assert.That(context.Result.ErrorDescription, Is.Null);
            Assert.That(context.Result.Subject?.Claims.FirstOrDefault(c => c.Type == Abstraction.Constants.ClaimNames.UserObjectId)?.Value, Is.EqualTo(userObjectId));
            Assert.That(context.Result.CustomResponse, Is.Not.Null);
        }
        using (Assert.EnterMultipleScope())
        {
            Assert.That(context.Result.CustomResponse[OidcConstants.TokenResponse.IssuedTokenType], Is.EqualTo(OidcConstants.TokenTypeIdentifiers.AccessToken));
            Assert.That((int)context.Result.CustomResponse[Abstraction.Constants.TokenExchange.AccessTokenLifetimeTemporaryClaimName], Is.LessThanOrEqualTo(plannedLifetime));
        }
    }

    [Test]
    public void CalculateAccessTokenLifetime_WhenSubjectTokenHasInvalidExpiration_ShouldSetErrorAndReturnZero()
    {
        // Arrange
        var subjectToken = "valid-token";
        var userObjectId = "user-actor";
        var clientId = "client-actor";
        var originalClientId = "client-123"; // the client which has received the subject token
        var claims = new[]
        {
            new Claim(Abstraction.Constants.ClaimNames.UserObjectId, userObjectId),
            new Claim(JwtClaimTypes.Issuer, "https://identityserver"),
            new Claim(JwtClaimTypes.Audience, clientId),
            new Claim(JwtClaimTypes.ClientId, originalClientId),
            new Claim(JwtClaimTypes.Email, "actor@b.com"),
            new Claim(JwtClaimTypes.Name, "Actor User"),
            new Claim(JwtClaimTypes.Expiration, "-1") // invalid expiration
        };
        var tokenValidationResult = new TokenValidationResult { Claims = claims, IsError = false };

        var context = CreateContextWithRaw(subjectToken);

        // Act
        var result = _validator.CalculateAccessTokenLifetime(tokenValidationResult, context);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result, Is.Zero);
            Assert.That(context.Result, Is.Not.Null);
        }
        using (Assert.EnterMultipleScope())
        {
            Assert.That(context.Result.IsError, Is.True, "Result should be error");
            Assert.That(context.Result.Error, Is.EqualTo("invalid_request"));
            Assert.That(context.Result.ErrorDescription, Does.Contain("subject_token expiration is invalid"));
        }
    }

    [Test]
    public void ExtractExpiresDateTime_WhenSubjectTokenHasInvalidExpiration_ShouldSetErrorAndReturnMin()
    {
        // Arrange
        var subjectToken = "valid-token";
        var userObjectId = "user-actor";
        var clientId = "client-actor";
        var originalClientId = "client-123"; // the client which has received the subject token
        var claims = new[]
        {
            new Claim(Abstraction.Constants.ClaimNames.UserObjectId, userObjectId),
            new Claim(JwtClaimTypes.Issuer, "https://identityserver"),
            new Claim(JwtClaimTypes.Audience, clientId),
            new Claim(JwtClaimTypes.ClientId, originalClientId),
            new Claim(JwtClaimTypes.Email, "actor@b.com"),
            new Claim(JwtClaimTypes.Name, "Actor User"),
            new Claim(JwtClaimTypes.Expiration, "-1") // invalid expiration
        };
        var tokenValidationResult = new TokenValidationResult { Claims = claims, IsError = false };

        var context = CreateContextWithRaw(subjectToken);

        // Act
        var result = _validator.ExtractExpiresDateTime(tokenValidationResult, context);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result, Is.EqualTo(DateTime.MinValue));
            Assert.That(context.Result, Is.Not.Null);
        }
        using (Assert.EnterMultipleScope())
        {
            Assert.That(context.Result.IsError, Is.True, "Result should be error");
            Assert.That(context.Result.Error, Is.EqualTo("invalid_request"));
            Assert.That(context.Result.ErrorDescription, Does.Contain("subject_token expiration is invalid"));
        }
    }

    [Test]
    public async Task ValidateAsync_WhenActorTokenClientIdMismatch_ShouldSetError()
    {
        // Arrange
        var subjectToken = "valid-token";
        var userObjectId = "user-actor";
        var clientId = "client-actor";
        var originalClientId = "client-123"; // the client which has received the subject token
        var requiredScope = Abstraction.Constants.ScopeNamesEntra.IdentityServerTokenExchangeScope;
        var plannedLifetime = 300;
        var plannedExpirationTime = DateTimeOffset.Now.AddSeconds(plannedLifetime).ToUnixTimeSeconds();
        var claims = new[]
        {
            new Claim(Abstraction.Constants.ClaimNames.UserObjectId, userObjectId),
            new Claim(JwtClaimTypes.Issuer, "https://login.microsoftonline.com/123"),
            new Claim(JwtClaimTypes.Audience, clientId),
            new Claim(JwtClaimTypes.ClientId, originalClientId),
            new Claim(Abstraction.Constants.ClaimNamesEntra.Scope, $"other {requiredScope}"),
            new Claim(JwtClaimTypes.Email, "actor@b.com"),
            new Claim(JwtClaimTypes.Name, "Actor User"),
            new Claim(JwtClaimTypes.Expiration, plannedExpirationTime.ToString())
        };
        var tokenValidationResult = new TokenValidationResult { Claims = claims, IsError = false };
        var tokenValidator = Substitute.For<ITokenValidator>();
        tokenValidator.ValidateAccessTokenAsync(subjectToken)
            .Returns(Task.FromResult(tokenValidationResult));
        _validatorSelector.SelectValidator(subjectToken).Returns(tokenValidator);

        // Setup actor token with mismatched clientId
        var actorToken = "actor-token";
        var actorClientId = "DIFFERENT_CLIENT_ID";
        var actorClaimObj = new Dictionary<string, object> { { JwtClaimTypes.ClientId, actorClientId } };
        var actorClaimJson = System.Text.Json.JsonSerializer.Serialize(actorClaimObj);
        var actorClaims = new[]
        {
            new Claim(JwtClaimTypes.Actor, actorClaimJson, IdentityServerConstants.ClaimValueTypes.Json)
        };
        var actorValidationResult = new TokenValidationResult { Claims = actorClaims, IsError = false };
        var actorValidator = Substitute.For<ITokenValidator>();
        actorValidator.ValidateAccessTokenAsync(actorToken)
            .Returns(Task.FromResult(actorValidationResult));
        _validatorSelector.SelectValidator(actorToken).Returns(actorValidator);

        var context = new ExtensionGrantValidationContext
        {
            Request = new ValidatedTokenRequest
            {
                Raw = new System.Collections.Specialized.NameValueCollection
                {
                    { Abstraction.Constants.TokenExchange.SubjectToken, subjectToken },
                    { Abstraction.Constants.TokenExchange.SubjectTokenType, Abstraction.Constants.TokenTypes.AccessToken },
                    { Abstraction.Constants.TokenExchange.ActorToken, actorToken },
                    { Abstraction.Constants.TokenExchange.ActorTokenType, Abstraction.Constants.TokenTypes.AccessToken }
                },
                Client = new Client { ClientId = clientId },
                Secret = new ParsedSecret { Type = IdentityServerConstants.ParsedSecretTypes.NoSecret }
            }
        };

        // Act
        await _validator.ValidateAsync(context);

        // Assert
        Assert.That(context.Result, Is.Not.Null);
        using (Assert.EnterMultipleScope())
        {
            Assert.That(context.Result.IsError, Is.True, "Result should be error");
            Assert.That(context.Result.Error, Is.EqualTo("invalid_client"));
            Assert.That(context.Result.ErrorDescription, Does.Contain("Client Ids must be the same"));
        }
    }

    [Test]
    public async Task ValidateIssuerSpecificClaims_WhenIssuerMissing_ShouldSetError()
    {
        // Arrange
        const string subjectClientId = "test-client-id";
        var context = CreateContextWithRaw();
        var claims = new[]
        {
            new Claim(JwtClaimTypes.Email, "user@domain.com"),
            new Claim(JwtClaimTypes.Name, "User Name")
            // No issuer claim
        };
        var result = new TokenValidationResult { Claims = claims };

        // Act
        await _validator.ValidateIssuerSpecificClaims(result, context, subjectClientId);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(context.Result.IsError, Is.True);
            Assert.That(context.Result.Error, Is.EqualTo("invalid_request"));
            Assert.That(context.Result.ErrorDescription, Is.EqualTo("subject_token is missing issuer claim"));
        }
    }

    [TestCase(null, false, true, "invalid_request", "subject_token issued by EntraID contains no scopes")]
    [TestCase("", false, true, "invalid_request", "subject_token issued by EntraID contains no scopes")]
    [TestCase("scope1 scope2 scope3", false, true, "invalid_request", $"subject_token issued by EntraID does not contain required scope '{Abstraction.Constants.ScopeNamesEntra.IdentityServerTokenExchangeScope}'")]
    [TestCase($"{Abstraction.Constants.ScopeNamesEntra.IdentityServerTokenExchangeScope} scope1 scope2", true, false, null, null)]
    [TestCase($"scope1 {Abstraction.Constants.ScopeNamesEntra.IdentityServerTokenExchangeScope} scope2", true, false, null, null)]
    [TestCase($"scope1 scope2 {Abstraction.Constants.ScopeNamesEntra.IdentityServerTokenExchangeScope}", true, false, null, null)]
    [TestCase(Abstraction.Constants.ScopeNamesEntra.IdentityServerTokenExchangeScope, true, false, null, null)]
    [TestCase($"  scope1   {Abstraction.Constants.ScopeNamesEntra.IdentityServerTokenExchangeScope}  scope2  ", true, false, null, null)]
    public void ValidateEntraIdTokenExchangeScope_WhenScopesClaimMissing_ShouldReturnFalseAndSetError(string scopes, bool expectedResult, bool expectError, string expectedError, string expectedErrorMsg)
    {
        // Arrange
        var context = CreateContextWithRaw();
        var claims = new List<Claim>
        {
            new(JwtClaimTypes.Email, "user@domain.com"),
            new(JwtClaimTypes.Name, "User Name")
        };

        if (scopes == null)
        {
            // No scopes claim
        }
        else
        {
            claims.Add(new Claim(Abstraction.Constants.ClaimNamesEntra.Scope, scopes));
        }

        var validationResult = new TokenValidationResult { Claims = claims };

        // Act
        var result = _validator.ValidateEntraIdTokenExchangeScope(validationResult, context);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result, Is.EqualTo(expectedResult));
            Assert.That(context.Result.ErrorDescription, Is.EqualTo(expectedErrorMsg));
        }
        // ValidationContext is instantiated with "invalid_grant" error by default, so should only be inspected in negative scenarios.
        if (expectError)
        {
            using (Assert.EnterMultipleScope())
            {
                Assert.That(context.Result.IsError, Is.EqualTo(expectError));
                Assert.That(context.Result.Error, Is.EqualTo(expectedError));
            }
        }
    }

    [Test]
    public void ValidateEntraIdTokenExchangeScope_WhenClaimsCollectionIsNull_ShouldReturnFalseAndSetError()
    {
        // Arrange
        const string expectedErrorMessage = "subject_token issued by EntraID contains no scopes";
        var context = CreateContextWithRaw();
        var validationResult = new TokenValidationResult { Claims = null };

        // Act
        var result = _validator.ValidateEntraIdTokenExchangeScope(validationResult, context);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result, Is.False);
            Assert.That(context.Result.IsError, Is.True);
            Assert.That(context.Result.Error, Is.EqualTo("invalid_request"));
            Assert.That(context.Result.ErrorDescription, Is.EqualTo(expectedErrorMessage));
        }
    }

    // Helper to create ExtensionGrantValidationContext with custom Raw for actor token
    private static ExtensionGrantValidationContext CreateContextWithActorRaw(string actorToken = "actor-token", string actorTokenType = null)
    {
        var raw = new System.Collections.Specialized.NameValueCollection
        {
            { Abstraction.Constants.TokenExchange.ActorToken, actorToken },
            { Abstraction.Constants.TokenExchange.ActorTokenType, actorTokenType ?? Abstraction.Constants.TokenTypes.AccessToken }
        };
        var request = new ValidatedTokenRequest { Raw = raw, Client = new Client() };
        return new ExtensionGrantValidationContext { Request = request };
    }

    // Helper to create ExtensionGrantValidationContext with custom Raw
    private static ExtensionGrantValidationContext CreateContextWithRaw(string subjectToken = "token", string subjectTokenType = null, string clientId = null)
    {
        var raw = new System.Collections.Specialized.NameValueCollection
        {
            { Abstraction.Constants.TokenExchange.SubjectToken, subjectToken },
            { Abstraction.Constants.TokenExchange.SubjectTokenType, subjectTokenType ?? Abstraction.Constants.TokenTypes.AccessToken }
        };
        var request = new ValidatedTokenRequest { Raw = raw, Client = new Client() { ClientId = clientId } };
        return new ExtensionGrantValidationContext { Request = request };
    }

    private void SetupClientStorage_AnyAsync(ClientExt client)
    {
        _clientStorage.AnyAsync(Arg.Any<System.Linq.Expressions.Expression<Func<ClientExt, bool>>>())
            .Returns(callInfo =>
            {
                var expression = callInfo.Arg<System.Linq.Expressions.Expression<Func<ClientExt, bool>>>();
                var compiledExpression = expression.Compile();
                return Task.FromResult(compiledExpression(client));
            });
    }
}
