// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

using Duende.IdentityServer.Models;
using Duende.IdentityServer.Services;
using Duende.IdentityServer.Stores;
using Duende.IdentityServer.Validation;
using Microsoft.AspNetCore.Http;
using Microsoft.Extensions.Logging;
using NSubstitute;
using IdentityServer.Services.Validation;

namespace IdentityServer.Test.Services.Validation;

[TestFixture]
public class CustomClientSecretValidatorTests
{
    private IClientStore _clientStore;
    private ISecretsListParser _parser;
    private ISecretsListValidator _validator;
    private IEventService _events;
    private ILogger<CustomClientSecretValidator> _logger;
    private CustomClientSecretValidator _sut;

    [SetUp]
    public void SetUp()
    {
        _clientStore = Substitute.For<IClientStore>();
        _parser = Substitute.For<ISecretsListParser>();
        _validator = Substitute.For<ISecretsListValidator>();
        _events = Substitute.For<IEventService>();
        _logger = Substitute.For<ILogger<CustomClientSecretValidator>>();
        _sut = new CustomClientSecretValidator(_clientStore, _parser, _validator, _events, _logger);
    }

    [Test]
    public async Task ValidateAsync_OnMissingClientId_ReturnsError()
    {
        // Arrange
        var context = new DefaultHttpContext();
        _parser.ParseAsync(context).Returns(Task.FromResult<ParsedSecret>(null));

        // Act
        var result = await _sut.ValidateAsync(context);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result.IsError, Is.True);
            Assert.That(result.Error, Is.EqualTo(Duende.IdentityModel.OidcConstants.TokenErrors.InvalidRequest));
            Assert.That(result.ErrorDescription, Is.EqualTo("No client identifier found in the request."));
        }
    }

    [Test]
    public async Task ValidateAsync_OnUnknownClient_ReturnsError()
    {
        // Arrange
        var context = new DefaultHttpContext();
        var parsedSecret = new ParsedSecret { Id = "unknown-client", Type = "SharedSecret" };
        _parser.ParseAsync(context).Returns(parsedSecret);
        _clientStore.FindEnabledClientByIdAsync(parsedSecret.Id).Returns(Task.FromResult<Client>(null));

        // Act
        var result = await _sut.ValidateAsync(context);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result.IsError, Is.True);
            Assert.That(result.ErrorDescription, Is.EqualTo("Client not found or not enabled."));
        }
    }

    [Test]
    public async Task ValidateAsync_OnInvalidClientSecret_ReturnsError()
    {
        // Arrange
        var context = new DefaultHttpContext();
        var parsedSecret = new ParsedSecret { Id = "client1", Type = "SharedSecret" };
        var client = new Client { ClientId = "client1", RequireClientSecret = true };
        _parser.ParseAsync(context).Returns(parsedSecret);
        _clientStore.FindEnabledClientByIdAsync(parsedSecret.Id).Returns(client);
        _validator.ValidateAsync(client.ClientSecrets, parsedSecret).Returns(new SecretValidationResult { Success = false });

        context.Request.Form = CreateForm("client_credentials");

        // Act
        var result = await _sut.ValidateAsync(context);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result.IsError, Is.True);
            Assert.That(result.ErrorDescription, Is.EqualTo("Invalid client secret."));
        }
    }

    [Test]
    public async Task ValidateAsync_OnPublicClientWithNonClientCredentials_SkipsSecretValidation()
    {
        // Arrange
        var context = new DefaultHttpContext();
        var parsedSecret = new ParsedSecret { Id = "public-client", Type = "NoSecret" };
        var client = new Client { ClientId = "public-client", RequireClientSecret = false };
        _parser.ParseAsync(context).Returns(parsedSecret);
        _clientStore.FindEnabledClientByIdAsync(parsedSecret.Id).Returns(client);

        context.Request.Form = CreateForm("authorization_code");

        // Act
        var result = await _sut.ValidateAsync(context);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result.IsError, Is.False);
            Assert.That(result.Client, Is.EqualTo(client));
        }
    }

    [Test]
    public async Task ValidateAsync_OnValidClientSecret_ReturnsSuccess()
    {
        // Arrange
        var context = new DefaultHttpContext();
        var parsedSecret = new ParsedSecret { Id = "client2", Type = "SharedSecret" };
        var client = new Client { ClientId = "client2", RequireClientSecret = true };
        var secretValidationResult = new SecretValidationResult { Success = true };
        _parser.ParseAsync(context).Returns(parsedSecret);
        _clientStore.FindEnabledClientByIdAsync(parsedSecret.Id).Returns(client);
        _validator.ValidateAsync(client.ClientSecrets, parsedSecret).Returns(secretValidationResult);

        context.Request.Form = CreateForm("client_credentials");

        // Act
        var result = await _sut.ValidateAsync(context);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result.IsError, Is.False);
            Assert.That(result.Client, Is.EqualTo(client));
            Assert.That(result.Secret, Is.EqualTo(parsedSecret));
            Assert.That(result.Confirmation, Is.EqualTo(secretValidationResult.Confirmation));
        }
    }

    private static FormCollection CreateForm(string grantType) =>
        new FormCollection(new Dictionary<string, Microsoft.Extensions.Primitives.StringValues>
        {
            { Duende.IdentityModel.OidcConstants.TokenRequest.GrantType, grantType }
        });
}
