// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

using System.Security.Claims;
using Duende.IdentityServer;
using Duende.IdentityServer.Models;
using Microsoft.Extensions.Logging.Abstractions;
using NSubstitute;
using NSubstitute.ExceptionExtensions;
using IdentityServer.Abstraction.Contracts.MicrosoftGraph;
using IdentityServer.Abstraction.Entities.EntraEntities;
using IdentityServer.Services.ApiRoles;
using IdentityServer.Services.ClientRoles;
using static IdentityServer.Abstraction.Constants;

namespace IdentityServer.Test;

[TestFixture]
public class CustomProfileServiceTests
{
    private IApiUserRoleClaimMapper _apiRoleMapper;
    private IClientUserRoleClaimMapper _clientRoleMapper;
    private IEntraUserService _userService;
    private CustomProfileService _service;

    [SetUp]
    public void SetUp()
    {
        _apiRoleMapper = Substitute.For<IApiUserRoleClaimMapper>();
        _clientRoleMapper = Substitute.For<IClientUserRoleClaimMapper>();
        _userService = Substitute.For<IEntraUserService>();
        _service = new CustomProfileService(_apiRoleMapper, _clientRoleMapper, NullLogger<CustomProfileService>.Instance, _userService);
    }

    #region IsActiveAsync Tests

    [Test]
    public async Task IsActiveAsync_WhenUserExistsAndIsActive_ShouldSetIsActiveToTrue()
    {
        // Arrange
        var userObjectId = "test-user-123";
        var context = CreateIsActiveContext(userObjectId);
        var userResponse = new UserResponse
        {
            Users = new List<User>
            {
                new() { OId = userObjectId, DisplayName = "Test User", AccountEnabled = true }
            }
        };

        _userService.GetUserByObjectIdAsync(userObjectId).Returns(userResponse);

        // Act
        await _service.IsActiveAsync(context);

        // Assert
        Assert.That(context.IsActive, Is.True);
        await _userService.Received(1).GetUserByObjectIdAsync(userObjectId);
    }

    [Test]
    public async Task IsActiveAsync_WhenUserDoesNotExist_ShouldSetIsActiveToFalse()
    {
        // Arrange
        var userObjectId = "non-existent-user";
        var context = CreateIsActiveContext(userObjectId);
        var userResponse = new UserResponse
        {
            Users = new List<User>() // empty list - user not found
        };

        _userService.GetUserByObjectIdAsync(userObjectId).Returns(userResponse);

        // Act
        await _service.IsActiveAsync(context);

        // Assert
        Assert.That(context.IsActive, Is.False);
        await _userService.Received(1).GetUserByObjectIdAsync(userObjectId);
    }

    [Test]
    public async Task IsActiveAsync_WhenGetUserByObjectIdAsyncReturnsNull_ShouldSetIsActiveToFalse()
    {
        // Arrange
        var userObjectId = "test-user-123";
        var context = CreateIsActiveContext(userObjectId);

        _userService.GetUserByObjectIdAsync(userObjectId).Returns((UserResponse)null);

        // Act
        await _service.IsActiveAsync(context);

        // Assert
        Assert.That(context.IsActive, Is.False);
        await _userService.Received(1).GetUserByObjectIdAsync(userObjectId);
    }

    [Test]
    public async Task IsActiveAsync_WhenUserObjectIdClaimIsMissing_ShouldSetIsActiveToFalse()
    {
        // Arrange
        var subject = new ClaimsPrincipal(new ClaimsIdentity()); // no UserObjectId claim
        var context = new IsActiveContext(subject, new Client(), "test-caller");

        // Act
        await _service.IsActiveAsync(context);

        // Assert
        Assert.That(context.IsActive, Is.False);
        await _userService.DidNotReceive().GetUserByObjectIdAsync(Arg.Any<string>());
    }

    [Test]
    public async Task IsActiveAsync_WhenUserObjectIdClaimIsEmpty_ShouldSetIsActiveToFalse()
    {
        // Arrange
        var context = CreateIsActiveContext(string.Empty);

        // Act
        await _service.IsActiveAsync(context);

        // Assert
        Assert.That(context.IsActive, Is.False);
        await _userService.DidNotReceive().GetUserByObjectIdAsync(Arg.Any<string>());
    }

    [Test]
    public async Task IsActiveAsync_WhenUserExistsButObjectIdDoesNotMatch_ShouldSetIsActiveToFalse()
    {
        // Arrange
        var userObjectId = "test-user-123";
        var differentObjectId = "different-user-456";
        var context = CreateIsActiveContext(userObjectId);
        var userResponse = new UserResponse
        {
            Users = new List<User>
            {
                new() { OId = differentObjectId, DisplayName = "Different User", AccountEnabled = true }
            }
        };

        _userService.GetUserByObjectIdAsync(userObjectId).Returns(userResponse);

        // Act
        await _service.IsActiveAsync(context);

        // Assert
        Assert.That(context.IsActive, Is.False);
        await _userService.Received(1).GetUserByObjectIdAsync(userObjectId);
    }

    [Test]
    public async Task IsActiveAsync_WhenMultipleUsersReturnedButNoneMatch_ShouldSetIsActiveToFalse()
    {
        // Arrange
        var userObjectId = "test-user-123";
        var context = CreateIsActiveContext(userObjectId);
        var userResponse = new UserResponse
        {
            Users = new List<User>
            {
                new() { OId = "different-user-1", DisplayName = "User 1", AccountEnabled = true },
                new() { OId = "different-user-2", DisplayName = "User 2", AccountEnabled = true }
            }
        };

        _userService.GetUserByObjectIdAsync(userObjectId).Returns(userResponse);

        // Act
        await _service.IsActiveAsync(context);

        // Assert
        Assert.That(context.IsActive, Is.False);
        await _userService.Received(1).GetUserByObjectIdAsync(userObjectId);
    }

    [Test]
    public async Task IsActiveAsync_WhenMultipleUsersReturnedAndOneMatches_ShouldSetIsActiveToTrue()
    {
        // Arrange
        var userObjectId = "test-user-123";
        var context = CreateIsActiveContext(userObjectId);
        var userResponse = new UserResponse
        {
            Users = new List<User>
            {
                new() { OId = "different-user-1", DisplayName = "User 1", AccountEnabled = true },
                new() { OId = userObjectId, DisplayName = "Test User", AccountEnabled = true },
                new() { OId = "different-user-2", DisplayName = "User 2", AccountEnabled = true }
            }
        };

        _userService.GetUserByObjectIdAsync(userObjectId).Returns(userResponse);

        // Act
        await _service.IsActiveAsync(context);

        // Assert
        Assert.That(context.IsActive, Is.True);
        await _userService.Received(1).GetUserByObjectIdAsync(userObjectId);
    }

    [Test]
    public async Task IsActiveAsync_WhenServiceThrowsException_ShouldSetIsActiveToFalseAndLogError()
    {
        // Arrange
        var userObjectId = "test-user-123";
        var context = CreateIsActiveContext(userObjectId);

        _userService.GetUserByObjectIdAsync(userObjectId).ThrowsAsync(new Exception("Service error"));

        // Act
        await _service.IsActiveAsync(context);

        // Assert
        Assert.That(context.IsActive, Is.False);
    }

    private static IsActiveContext CreateIsActiveContext(string userObjectId)
    {
        var claims = new List<Claim>();
        if (!string.IsNullOrEmpty(userObjectId))
        {
            claims.Add(new Claim(ClaimNames.UserObjectId, userObjectId));
        }

        var subject = new ClaimsPrincipal(new ClaimsIdentity(claims));
        return new IsActiveContext(subject, new Client(), "test-caller");
    }

    #endregion

    [Test]
    public async Task GetProfileDataAsync_WhenCalled_ShouldCallCorrectHandlers()
    {
        // Arrange
        var context = TestHelpers.CreateProfileDataRequestContext(IdentityServerConstants.ProfileDataCallers.ClaimsProviderAccessToken);

        // Act
        await _service.GetProfileDataAsync(context);

        // Assert
        Assert.That(context.IssuedClaims, Is.Not.Null);
    }

    [Test]
    public void AddIssuedClaim_WhenClaimExists_ShouldAddClaim()
    {
        // Arrange
        var context = TestHelpers.CreateProfileDataRequestContext();
        var claim = new Claim(ClaimNames.UserObjectId, "123");
        context.Subject = new ClaimsPrincipal(new ClaimsIdentity(new[] { claim }));

        // Act
        var result = CustomProfileService.AddIssuedClaim(context, ClaimNames.UserObjectId);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(context.IssuedClaims, Has.Count.EqualTo(1));
            Assert.That(context.IssuedClaims[0].Type, Is.EqualTo(ClaimNames.UserObjectId));
            Assert.That(context.IssuedClaims[0].Value, Is.EqualTo("123"));
            Assert.That(result.Type, Is.EqualTo(ClaimNames.UserObjectId));
            Assert.That(result.Value, Is.EqualTo("123"));
        }
    }

    [Test]
    public void AddIssuedClaim_WhenClaimMissing_ShouldReturnNull()
    {
        // Arrange
        var context = TestHelpers.CreateProfileDataRequestContext();

        // Act
        var result = CustomProfileService.AddIssuedClaim(context, "missing");

        // Assert
        Assert.That(result, Is.Null);
    }

    [Test]
    public void AddNameIssuedClaim_WhenNameExists_ShouldAddNameClaim()
    {
        // Arrange
        var context = TestHelpers.CreateProfileDataRequestContext();
        context.Subject = new ClaimsPrincipal(new ClaimsIdentity(new[] { new Claim("name", "TestName") }, "test", "name", "role"));

        // Act
        CustomProfileService.AddNameIssuedClaim(context);

        // Assert
        Assert.That(context.IssuedClaims.Any(c => c.Type == ClaimNames.UserDisplayName && c.Value == "TestName"), Is.True);
    }

    [Test]
    public async Task HandleAccessTokenClaims_WhenCalled_ShouldAddClaims()
    {
        // Arrange
        var context = TestHelpers.CreateProfileDataRequestContext(resources: new ApiResource("api1"));
        var claim = new Claim(ClaimNames.UserObjectId, "123");
        _userService.GetUserOnPremisePropertiesAsync("123").Returns(new Dictionary<string, string> { { ClaimNames.UserOnPremisesSamAccountName, "samAccount" } });

        // Act
        await _service.HandleAccessTokenClaims(context, claim);

        // Assert
        Assert.That(context.IssuedClaims, Is.Not.Null);
    }

    [Test]
    public async Task AddApiRoleClaims_WhenUserObjectIdPresent_ShouldAddClaims()
    {
        // Arrange
        var context = TestHelpers.CreateProfileDataRequestContext();
        var claim = new Claim(ClaimNames.UserObjectId, "123");
        var claims = new[] { new Claim("role", "api") };
        _apiRoleMapper.ProcessApiRoleMappingsForUserAsync(Arg.Any<IEnumerable<string>>(), "123")
                .Returns(claims.ToAsyncEnumerable());

        // Act
        await _service.AddApiRoleClaims(context, claim);

        // Assert
        Assert.That(context.IssuedClaims, Has.Exactly(1).EqualTo(claims[0]));
    }

    [Test]
    public async Task AddApiRoleClaims_WhenUserObjectIdMissing_ShouldDoNothing()
    {
        // Arrange
        var context = TestHelpers.CreateProfileDataRequestContext();

        // Act
        await _service.AddApiRoleClaims(context, null);

        // Assert
        Assert.That(context.IssuedClaims, Is.Empty);
    }

    [Test]
    public async Task AddUserProperties_WhenCalled_ShouldAddClaims()
    {
        // Arrange
        var context = TestHelpers.CreateProfileDataRequestContext();
        var claim = new Claim(ClaimNames.UserObjectId, "123");
        var properties = new Dictionary<string, string> { { "prop", "val" } };
        _userService.GetUserOnPremisePropertiesAsync("123").Returns(properties);

        // Act
        await _service.AddUserProperties(context, claim);

        // Assert
        Assert.That(context.IssuedClaims.Any(c => c.Type == "prop" && c.Value == "val"), Is.True);
    }

    [Test]
    public async Task AddUserInfoClaims_WhenCalled_ShouldAddClaims()
    {
        // Arrange
        var context = TestHelpers.CreateProfileDataRequestContext();
        var claim = new Claim(ClaimNames.UserObjectId, "123");
        var properties = new Dictionary<string, string> { { "info", "value" } };
        _userService.GetUserPropertiesAsync("123").Returns(properties);

        // Act
        await _service.AddUserInfoClaims(context, claim);

        // Assert
        Assert.That(context.IssuedClaims.Any(c => c.Type == "info" && c.Value == "value"), Is.True);
    }

    [Test]
    public async Task HandleIdTokenClaims_WhenCalled_ShouldAddClaims()
    {
        // Arrange
        var context = TestHelpers.CreateProfileDataRequestContext();
        var claim = new Claim(ClaimNames.UserObjectId, "123");
        _userService.GetUserOnPremisePropertiesAsync("123").Returns(new Dictionary<string, string> { { ClaimNames.UserOnPremisesSamAccountName, "samAccount" } });

        // Act
        await _service.HandleIdTokenClaims(context, claim);

        // Assert
        Assert.That(context.IssuedClaims, Is.Not.Null);
    }

    [Test]
    public async Task AddClientRoleClaims_WhenUserObjectIdPresent_ShouldAddClaims()
    {
        // Arrange
        var context = TestHelpers.CreateProfileDataRequestContext();
        context.Client = new Client { ClientId = "client1" };
        var claim = new Claim(ClaimNames.UserObjectId, "123");
        var claims = new[] { new Claim("role", "client") };
        _clientRoleMapper.ProcessClientRoleMappingsForUserAsync("client1", "123")
            .Returns(claims.ToAsyncEnumerable());

        // Act
        await _service.AddClientRoleClaims(context, claim);

        // Assert
        Assert.That(context.IssuedClaims, Has.Exactly(1).EqualTo(claims[0]));
    }

    [Test]
    public async Task AddClientRoleClaims_WhenUserObjectIdMissing_ShouldDoNothing()
    {
        // Arrange
        var context = TestHelpers.CreateProfileDataRequestContext();

        // Act
        await _service.AddClientRoleClaims(context, null);

        // Assert
        Assert.That(context.IssuedClaims, Is.Empty);
    }

    [Test]
    public void HandleTokenExchangeClaims_WhenNotTokenExchange_ShouldDoNothing()
    {
        // Arrange
        var identity = new ClaimsIdentity();
        identity.AddClaim(new Claim(Duende.IdentityModel.JwtClaimTypes.AuthenticationMethod, "not-token-exchange"));
        var subject = new ClaimsPrincipal(identity);
        var context = new ProfileDataRequestContext(subject, new Client(), "", new List<string>());

        // Act
        typeof(CustomProfileService)
       .GetMethod("HandleTokenExchangeClaims", System.Reflection.BindingFlags.NonPublic | System.Reflection.BindingFlags.Static)
             .Invoke(null, new object[] { context });

        // Assert
        Assert.That(context.IssuedClaims, Is.Empty);
    }

    [Test]
    public void HandleTokenExchangeClaims_WhenTokenExchangeAndActorExists_ShouldAddActorClaim()
    {
        // Arrange
        var identity = new ClaimsIdentity();
        identity.AddClaim(new Claim(Duende.IdentityModel.JwtClaimTypes.AuthenticationMethod, Duende.IdentityModel.OidcConstants.GrantTypes.TokenExchange));
        identity.AddClaim(new Claim(Duende.IdentityModel.JwtClaimTypes.Actor, "actor-value"));
        var subject = new ClaimsPrincipal(identity);
        var context = new ProfileDataRequestContext(subject, new Client(), "", new List<string>());

        // Act
        typeof(CustomProfileService)
  .GetMethod("HandleTokenExchangeClaims", System.Reflection.BindingFlags.NonPublic | System.Reflection.BindingFlags.Static)
            .Invoke(null, new object[] { context });

        // Assert
        Assert.That(context.IssuedClaims, Has.Count.EqualTo(1));
        using (Assert.EnterMultipleScope())
        {
            Assert.That(context.IssuedClaims[0].Type, Is.EqualTo(Duende.IdentityModel.JwtClaimTypes.Actor));
            Assert.That(context.IssuedClaims[0].Value, Is.EqualTo("actor-value"));
        }
    }

    [Test]
    public void HandleTokenExchangeClaims_WhenTokenExchangeAndNoActorClaim_ShouldDoNothing()
    {
        // Arrange
        var identity = new ClaimsIdentity();
        identity.AddClaim(new Claim(Duende.IdentityModel.JwtClaimTypes.AuthenticationMethod, Duende.IdentityModel.OidcConstants.GrantTypes.TokenExchange));
        var subject = new ClaimsPrincipal(identity);
        var context = new ProfileDataRequestContext(subject, new Client(), "", new List<string>());

        // Act
        typeof(CustomProfileService)
                   .GetMethod("HandleTokenExchangeClaims", System.Reflection.BindingFlags.NonPublic | System.Reflection.BindingFlags.Static)
             .Invoke(null, new object[] { context });

        // Assert
        Assert.That(context.IssuedClaims, Is.Empty);
    }
}

// Helper class for test context creation
public static class TestHelpers
{
    public static ProfileDataRequestContext CreateProfileDataRequestContext(string caller = "", ApiResource resources = null)
    {
        var subject = new ClaimsPrincipal(new ClaimsIdentity());
        var client = new Client();
        var context = new ProfileDataRequestContext(subject, client, caller, new List<string>());
        if (resources != null)
        {
            context.RequestedResources = new Duende.IdentityServer.Validation.ResourceValidationResult
            {
                Resources = new Resources { ApiResources = new List<ApiResource> { resources } },
            };
        }
        else
        {
            context.RequestedResources = new Duende.IdentityServer.Validation.ResourceValidationResult
            {
                Resources = new Resources(),
            };
        }
        return context;
    }
}
