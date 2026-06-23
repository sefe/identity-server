// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

using System.Security.Claims;
using Duende.IdentityServer.Models;
using Duende.IdentityServer.Validation;
using Microsoft.Extensions.Logging;
using NSubstitute;
using IdentityServer.Abstraction.Entities.IdentityServerConfig;
using IdentityServer.Services.ApiRoles;

namespace IdentityServer.Test.Services.ApiRoles;

[TestFixture]
public class ApiClientCredentialsRoleMapperTests
{
    private IApiClientRoleClaimMapper _roleToClaimMapper;
    private ILogger<ApiClientCredentialsRoleMapper> _logger;
    private ApiClientCredentialsRoleMapper _sut;

    [SetUp]
    public void SetUp()
    {
        _roleToClaimMapper = Substitute.For<IApiClientRoleClaimMapper>();
        _logger = Substitute.For<ILogger<ApiClientCredentialsRoleMapper>>();
        _sut = new ApiClientCredentialsRoleMapper(_roleToClaimMapper, _logger);
    }

    [Test]
    public async Task ValidateAsync_GrantTypeNotClientCredentials_DoesNothing()
    {
        // Arrange
        var context = new CustomTokenRequestValidationContext
        {
            Result = new TokenRequestValidationResult(
                new ValidatedTokenRequest
                {
                    GrantType = "password", // Not client_credentials
                    ClientClaims = new List<Claim>(),
                    ValidatedResources = new ResourceValidationResult(new Resources())
                })
        };

        // Act
        await _sut.ValidateAsync(context);

        // Assert
        Assert.That(context.Result.ValidatedRequest.ClientClaims, Is.Empty);
        _roleToClaimMapper.DidNotReceiveWithAnyArgs().ProcessApiRoleMappingsForClientIdAsync(default, default);
    }

    [Test]
    public async Task ValidateAsync_GrantTypeClientCredentials_AddsM2MClaimAndRoleClaims()
    {
        // Arrange
        var apiResourceNames = new[] { "api1", "api2" };
        var clientId = "test-client";
        var m2mClaimType = Abstraction.Constants.ClaimNames.M2M;

        var apiResources = apiResourceNames.Select(name => new ApiResource(name)).ToList();
        var validatedResources = new Resources(Enumerable.Empty<IdentityResource>(), apiResources, Enumerable.Empty<ApiScope>());
        var clientClaims = new List<Claim>();

        var validatedRequest = new ValidatedTokenRequest
        {
            GrantType = ClientGrantTypeNames.Grant_ClientCredentials,
            ClientId = clientId,
            ClientClaims = clientClaims,
            ValidatedResources = new ResourceValidationResult(validatedResources)
        };

        var context = new CustomTokenRequestValidationContext
        {
            Result = new TokenRequestValidationResult(validatedRequest)
        };

        var roleClaims = new[]
        {
            new Claim("role", "admin"),
            new Claim("role", "user"),
            null // Should be ignored
        };

        _roleToClaimMapper
            .ProcessApiRoleMappingsForClientIdAsync(
                Arg.Is<IEnumerable<string>>(x => x.SequenceEqual(apiResourceNames)),
                clientId)
            .Returns(roleClaims.ToAsyncEnumerable());

        // Act
        await _sut.ValidateAsync(context);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            // M2M claim is added
            Assert.That(clientClaims.Any(c => c.Type == m2mClaimType && c.Value == bool.TrueString), Is.True);
            // Role claims are added (null ignored)
            Assert.That(clientClaims.Any(c => c.Type == "role" && c.Value == "admin"), Is.True);
            Assert.That(clientClaims.Any(c => c.Type == "role" && c.Value == "user"), Is.True);
            Assert.That(clientClaims, Has.Count.EqualTo(3)); // 2 roles + 1 m2m
        }
    }
}
