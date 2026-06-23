// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

using NSubstitute;
using IdentityServer.Abstraction.Entities.EntraEntities;
using static IdentityServer.Abstraction.Constants;

namespace IdentityServer.MicrosoftGraph.Tests;

[TestFixture]
public class EntraUserServiceTests
{
    private IMicrosoftGraphUserApi _mockGraphUserApi;
    private EntraUserService _service;

    [SetUp]
    public void SetUp()
    {
        _mockGraphUserApi = Substitute.For<IMicrosoftGraphUserApi>();
        _service = new EntraUserService(_mockGraphUserApi);
    }

    [Test]
    public async Task GetUsersByDisplayNameAsync_WithValidSearchString_ReturnsUsersWithNullSkipToken()
    {
        // Arrange
        var searchString = "John Doe";
        var expectedUsers = new UserResponse
        {
            Users = [new User { OId = "123", DisplayName = "John Doe" }],
            SkipToken = "some-token"
        };
        _mockGraphUserApi.SearchUsersByDisplayNameAsync(searchString).Returns(expectedUsers);

        // Act
        var result = await _service.GetUsersByDisplayNameAsync(searchString);

        // Assert
        Assert.That(result, Is.Not.Null);
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result.Users, Has.Count.EqualTo(1));
            Assert.That(result.Users[0].OId, Is.EqualTo("123"));
            Assert.That(result.SkipToken, Is.Null);
        }
        await _mockGraphUserApi.Received(1).SearchUsersByDisplayNameAsync(searchString);
    }

    [TestCase(true)]
    [TestCase(false)]
    [TestCase(null)]
    public async Task GetUserByObjectIdAsync_ReturnsUserResponse_WhenUserIsFound(bool? accountEnabled)
    {
        // Arrange
        var userId = "user-id-123";
        var expectedResponse = new UserResponse
        {
            Users = [new User { OId = userId, DisplayName = "Test User", AccountEnabled = accountEnabled }]
        };
        _mockGraphUserApi.GetUserByObjectIdAsync(userId).Returns(expectedResponse);

        // Act
        var result = await _service.GetUserByObjectIdAsync(userId);

        // Assert
        Assert.That(result, Is.Not.Null);
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result.Users, Has.Count.EqualTo(1));
            Assert.That(result.Users[0].OId, Is.EqualTo(userId));
        }
        await _mockGraphUserApi.Received(1).GetUserByObjectIdAsync(userId);
    }

    [Test]
    public async Task GetUsersByObjectIdsAsync_WithValidUserIds_ReturnsUserResponse()
    {
        // Arrange
        var userIds = new[] { "user-1", "user-2", "user-3" };
        var expectedResponse = new UserResponse
        {
            Users = [
                new User { OId = "user-1", DisplayName = "User 1" },
                new User { OId = "user-2", DisplayName = "User 2" },
                new User { OId = "user-3", DisplayName = "User 3" }
            ]
        };
        _mockGraphUserApi.GetUsersByObjectIdsAsync(userIds).Returns(expectedResponse);

        // Act
        var result = await _service.GetUsersByObjectIdsAsync(userIds);

        // Assert
        Assert.That(result, Is.Not.Null);
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result.Users, Has.Count.EqualTo(3));
            Assert.That(result.Users.Select(u => u.OId), Is.EquivalentTo(userIds));
        }
        await _mockGraphUserApi.Received(1).GetUsersByObjectIdsAsync(userIds);
    }

    [Test]
    public async Task GetUserMembershipInGroups_WithValidParameters_ReturnsGroups()
    {
        // Arrange
        var userId = "user-id-123";
        var groupIdFilter = new[] { "group-1", "group-2", "group-3" };
        var expectedGroups = new List<Group>
        {
            new() { Id = "group-1", DisplayName = "Group 1" },
            new() { Id = "group-3", DisplayName = "Group 3" }
        };
        var groupResponse = new GroupResponse { Groups = expectedGroups };
        _mockGraphUserApi.GetUserMembershipInGroups(userId, groupIdFilter).Returns(groupResponse);

        // Act
        var result = await _service.GetUserMembershipInGroups(userId, groupIdFilter);

        // Assert
        Assert.That(result, Is.Not.Null);
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result, Has.Count.EqualTo(2));
            Assert.That(result.Select(g => g.Id), Is.EquivalentTo(new List<string> { "group-1", "group-3" }));
        }
        await _mockGraphUserApi.Received(1).GetUserMembershipInGroups(userId, groupIdFilter);
    }

    [Test]
    public async Task GetUserMembershipInGroups_WithNullResponse_ReturnsEmptyList()
    {
        // Arrange
        var userId = "user-id-123";
        var groupIdFilter = new[] { "group-1", "group-2" };
        _mockGraphUserApi.GetUserMembershipInGroups(userId, groupIdFilter).Returns((GroupResponse)null!);

        // Act
        var result = await _service.GetUserMembershipInGroups(userId, groupIdFilter);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result, Is.Not.Null);
            Assert.That(result, Is.Empty);
        }
        await _mockGraphUserApi.Received(1).GetUserMembershipInGroups(userId, groupIdFilter);
    }

    [Test]
    public async Task GetUserMembershipInGroups_WithNullGroupsResponse_ReturnsEmptyList()
    {
        // Arrange
        var userId = "user-id-123";
        var groupIdFilter = new[] { "group-1", "group-2" };
        var groupResponse = new GroupResponse { Groups = null! };
        _mockGraphUserApi.GetUserMembershipInGroups(userId, groupIdFilter).Returns(groupResponse);

        // Act
        var result = await _service.GetUserMembershipInGroups(userId, groupIdFilter);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result, Is.Not.Null);
            Assert.That(result, Is.Empty);
        }
        await _mockGraphUserApi.Received(1).GetUserMembershipInGroups(userId, groupIdFilter);
    }

    [Test]
    public async Task GetUserOnPremisePropertiesAsync_WithValidResponse_ReturnsCorrectDictionary()
    {
        // Arrange
        var userId = "user-id-123";
        var name = "testuser";
        var response = new UserOnPremisePropertiesResponse
        {
            OnPremisesSamAccountName = name
        };
        _mockGraphUserApi.GetUserOnPremisePropertiesAsync(userId).Returns(response);

        // Act
        var result = await _service.GetUserOnPremisePropertiesAsync(userId);

        // Assert
        Assert.That(result, Is.Not.Null);
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result, Has.Count.EqualTo(1));
            Assert.That(result[ClaimNames.UserOnPremisesSamAccountName], Is.EqualTo(name));
        }
        await _mockGraphUserApi.Received(1).GetUserOnPremisePropertiesAsync(userId);
    }

    [Test]
    public async Task GetUserOnPremisePropertiesAsync_WithNullResponse_ReturnsEmptyDictionary()
    {
        // Arrange
        var userId = "user-id-123";
        _mockGraphUserApi.GetUserOnPremisePropertiesAsync(userId).Returns((UserOnPremisePropertiesResponse?)null);

        // Act
        var result = await _service.GetUserOnPremisePropertiesAsync(userId);

        // Assert
        Assert.That(result, Is.Not.Null);
        Assert.That(result, Is.Empty);
        await _mockGraphUserApi.Received(1).GetUserOnPremisePropertiesAsync(userId);
    }

    [Test]
    public async Task GetUserOnPremisePropertiesAsync_WithEmptyValues_ReturnsEmptyDictionary()
    {
        // Arrange
        var userId = "user-id-123";
        var response = new UserOnPremisePropertiesResponse
        {
            OnPremisesSamAccountName = ""
        };
        _mockGraphUserApi.GetUserOnPremisePropertiesAsync(userId).Returns(response);

        // Act
        var result = await _service.GetUserOnPremisePropertiesAsync(userId);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result, Is.Not.Null);
            Assert.That(result, Is.Empty);
        }
        await _mockGraphUserApi.Received(1).GetUserOnPremisePropertiesAsync(userId);
    }

    [Test]
    public async Task GetUserPropertiesAsync_WithValidResponse_ReturnsCorrectDictionary()
    {
        // Arrange
        var userId = "user-id-123";
        var response = new UserAdditionalPropertiesResponse
        {
            OId = "object-id-123",
            DisplayName = "John Doe",
            GivenName = "John",
            JobTitle = "Software Engineer",
            Mail = "john.doe@example.com",
            MobilePhone = "+1234567890",
            OfficeLocation = "Seattle",
            PreferredLanguage = "en-US",
            Surname = "Doe",
            UserPrincipalName = "john.doe@company.com"
        };
        _mockGraphUserApi.GetUserPropertiesAsync(userId).Returns(response);

        // Act
        var result = await _service.GetUserPropertiesAsync(userId);

        // Assert
        Assert.That(result, Is.Not.Null);
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result, Has.Count.EqualTo(10));
            Assert.That(result[ClaimNames.UserObjectId], Is.EqualTo("object-id-123"));
            Assert.That(result[ClaimNames.UserDisplayName], Is.EqualTo("John Doe"));
            Assert.That(result["givenName"], Is.EqualTo("John"));
            Assert.That(result["jobTitle"], Is.EqualTo("Software Engineer"));
            Assert.That(result[ClaimNames.UserEmail], Is.EqualTo("john.doe@example.com"));
            Assert.That(result["mobilePhone"], Is.EqualTo("+1234567890"));
            Assert.That(result["officeLocation"], Is.EqualTo("Seattle"));
            Assert.That(result["preferredLanguage"], Is.EqualTo("en-US"));
            Assert.That(result["surname"], Is.EqualTo("Doe"));
            Assert.That(result[ClaimNames.UserPrincipalName], Is.EqualTo("john.doe@company.com"));
        }
        await _mockGraphUserApi.Received(1).GetUserPropertiesAsync(userId);
    }

    [Test]
    public async Task GetUserPropertiesAsync_WithNullResponse_ReturnsEmptyDictionary()
    {
        // Arrange
        var userId = "user-id-123";
        _mockGraphUserApi.GetUserPropertiesAsync(userId).Returns((UserAdditionalPropertiesResponse?)null);

        // Act
        var result = await _service.GetUserPropertiesAsync(userId);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result, Is.Not.Null);
            Assert.That(result, Is.Empty);
        }
        await _mockGraphUserApi.Received(1).GetUserPropertiesAsync(userId);
    }

    [Test]
    public async Task GetUserPropertiesAsync_WithPartialValues_ReturnsOnlyNonEmptyValues()
    {
        // Arrange
        var userId = "user-id-123";
        var response = new UserAdditionalPropertiesResponse
        {
            OId = "object-id-123",
            DisplayName = "John Doe",
            GivenName = "", // empty string
            JobTitle = null, // null value
            Mail = "john.doe@example.com",
            MobilePhone = " ", // whitespace only
            OfficeLocation = null,
            PreferredLanguage = "en-US",
            Surname = "",
            UserPrincipalName = "john.doe@company.com"
        };
        _mockGraphUserApi.GetUserPropertiesAsync(userId).Returns(response);

        // Act
        var result = await _service.GetUserPropertiesAsync(userId);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result, Is.Not.Null);
            Assert.That(result, Has.Count.EqualTo(6)); // Only non-null, non-empty values
            Assert.That(result[ClaimNames.UserObjectId], Is.EqualTo("object-id-123"));
            Assert.That(result[ClaimNames.UserDisplayName], Is.EqualTo("John Doe"));
            Assert.That(result[ClaimNames.UserEmail], Is.EqualTo("john.doe@example.com"));
            Assert.That(result["mobilePhone"], Is.EqualTo(" ")); // Whitespace is preserved
            Assert.That(result["preferredLanguage"], Is.EqualTo("en-US"));
            Assert.That(result[ClaimNames.UserPrincipalName], Is.EqualTo("john.doe@company.com"));

            // Verify that empty and null values are not included
            Assert.That(result.ContainsKey("givenName"), Is.False);
            Assert.That(result.ContainsKey("jobTitle"), Is.False);
            Assert.That(result.ContainsKey("officeLocation"), Is.False);
            Assert.That(result.ContainsKey("surname"), Is.False);
        }
        await _mockGraphUserApi.Received(1).GetUserPropertiesAsync(userId);
    }

    [Test]
    public async Task GetUserPropertiesAsync_WithCaseInsensitiveDictionary_AllowsCaseInsensitiveLookup()
    {
        // Arrange
        var userId = "user-id-123";
        var response = new UserAdditionalPropertiesResponse
        {
            DisplayName = "John Doe"
        };
        _mockGraphUserApi.GetUserPropertiesAsync(userId).Returns(response);

        // Act
        var result = await _service.GetUserPropertiesAsync(userId);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result, Is.Not.Null);
            Assert.That(result[ClaimNames.UserDisplayName], Is.EqualTo("John Doe"));
            Assert.That(result["NAME"], Is.EqualTo("John Doe")); // Case insensitive lookup
            Assert.That(result["Name"], Is.EqualTo("John Doe")); // Case insensitive lookup
        }
    }
}
