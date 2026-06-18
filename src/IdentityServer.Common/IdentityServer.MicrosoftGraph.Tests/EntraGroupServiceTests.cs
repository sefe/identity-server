using NSubstitute;
using IdentityServer.Abstraction.Entities.EntraEntities;

namespace IdentityServer.MicrosoftGraph.Tests;

[TestFixture]
public class EntraGroupServiceTests
{
    private IMicrosoftGraphGroupApi _mockGraphGroupApi;
    private EntraGroupService _service;

    [SetUp]
    public void SetUp()
    {
        _mockGraphGroupApi = Substitute.For<IMicrosoftGraphGroupApi>();
        _service = new EntraGroupService(_mockGraphGroupApi);
    }

    [Test]
    public async Task GetGroupByObjectIdAsync_WithValidGroupId_ReturnsGroupResponse()
    {
        // Arrange
        var groupId = Guid.NewGuid();
        var expectedResponse = new GroupResponse
        {
            Groups = [new Group { Id = groupId.ToString(), DisplayName = "Test Group" }]
        };
        _mockGraphGroupApi.GetGroupByObjectIdAsync(groupId).Returns(expectedResponse);

        // Act
        var result = await _service.GetGroupByObjectIdAsync(groupId.ToString());

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result, Is.Not.Null);
            Assert.That(result.Groups, Has.Count.EqualTo(1));
            Assert.That(result.Groups[0].Id, Is.EqualTo(groupId.ToString()));
            Assert.That(result.Groups[0].DisplayName, Is.EqualTo("Test Group"));
        }
        await _mockGraphGroupApi.Received(1).GetGroupByObjectIdAsync(groupId);
    }

    [TestCase("not-a-guid")]
    [TestCase("00000000-0000-0000-0000-000000000000")]
    [TestCase("")]
    [TestCase("   ")]
    [TestCase(null)]
    public async Task GetGroupByObjectIdAsync_WithInvalidOrEmptyGuid_ReturnsEmptyResponse(string? groupId)
    {
        // Act
        var result = await _service.GetGroupByObjectIdAsync(groupId!);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result, Is.Not.Null);
            Assert.That(result.Groups, Is.Empty);
        }
        await _mockGraphGroupApi.DidNotReceive().GetGroupByObjectIdAsync(Arg.Any<Guid>());
    }

    [Test]
    public async Task GetGroupsByObjectIdsAsync_WithValidGroupIds_ReturnsGroupResponse()
    {
        // Arrange
        var groupId1 = Guid.NewGuid();
        var groupId2 = Guid.NewGuid();
        var groupId3 = Guid.NewGuid();
        var groupIds = new[] { groupId1.ToString(), groupId2.ToString(), groupId3.ToString() };
        var expectedResponse = new GroupResponse
        {
            Groups = [
                new Group { Id = groupId1.ToString(), DisplayName = "Group 1" },
                new Group { Id = groupId2.ToString(), DisplayName = "Group 2" },
                new Group { Id = groupId3.ToString(), DisplayName = "Group 3" }
            ]
        };
        _mockGraphGroupApi.GetGroupsByObjectIdsAsync(Arg.Any<IEnumerable<Guid>>()).Returns(expectedResponse);

        // Act
        var result = await _service.GetGroupsByObjectIdsAsync(groupIds);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result, Is.Not.Null);
            Assert.That(result.Groups, Has.Count.EqualTo(3));
            Assert.That(result.Groups.Select(g => g.Id), Is.EquivalentTo(groupIds));
        }
        await _mockGraphGroupApi.Received(1).GetGroupsByObjectIdsAsync(Arg.Is<IEnumerable<Guid>>(ids => ids.Count() == 3));
    }

    [Test]
    public async Task GetGroupsByObjectIdsAsync_WithMixedValidAndInvalidIds_ReturnsOnlyValidGroups()
    {
        // Arrange
        var validGroupId1 = Guid.NewGuid();
        var validGroupId2 = Guid.NewGuid();
        var groupIds = new[] { validGroupId1.ToString(), "invalid-guid", validGroupId2.ToString(), Guid.Empty.ToString() };
        var expectedResponse = new GroupResponse
        {
            Groups = [
                new Group { Id = validGroupId1.ToString(), DisplayName = "Group 1" },
                new Group { Id = validGroupId2.ToString(), DisplayName = "Group 2" }
          ]
        };
        _mockGraphGroupApi.GetGroupsByObjectIdsAsync(Arg.Any<IEnumerable<Guid>>()).Returns(expectedResponse);

        // Act
        var result = await _service.GetGroupsByObjectIdsAsync(groupIds);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result, Is.Not.Null);
            Assert.That(result.Groups, Has.Count.EqualTo(2));
        }
        await _mockGraphGroupApi.Received(1).GetGroupsByObjectIdsAsync(
                    Arg.Is<IEnumerable<Guid>>(ids => ids.Count() == 2 && ids.Contains(validGroupId1) && ids.Contains(validGroupId2)));
    }

    [Test]
    public async Task GetGroupsByObjectIdsAsync_WithAllInvalidIds_ReturnsEmptyResponse()
    {
        // Arrange
        var groupIds = new[] { "invalid-guid-1", "invalid-guid-2", Guid.Empty.ToString() };

        // Act
        var result = await _service.GetGroupsByObjectIdsAsync(groupIds);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result, Is.Not.Null);
            Assert.That(result.Groups, Is.Empty);
        }
        await _mockGraphGroupApi.DidNotReceive().GetGroupsByObjectIdsAsync(Arg.Any<IEnumerable<Guid>>());
    }

    [Test]
    public async Task GetGroupsByObjectIdsAsync_WithEmptyCollection_ReturnsEmptyResponse()
    {
        // Arrange
        var groupIds = Array.Empty<string>();

        // Act
        var result = await _service.GetGroupsByObjectIdsAsync(groupIds);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result, Is.Not.Null);
            Assert.That(result.Groups, Is.Empty);
        }
        await _mockGraphGroupApi.DidNotReceive().GetGroupsByObjectIdsAsync(Arg.Any<IEnumerable<Guid>>());
    }

    [TestCase(null, null)]
    [TestCase("currentToken", "nextPageToken")]
    public async Task GetGroupMembersAsync_WithValidGroupId_ReturnsUsersWithSkipToken(string? inputToken, string? expectedSkipToken)
    {
        // Arrange
        var groupId = Guid.NewGuid();
        var nextLink = expectedSkipToken != null ? $"https://graph.microsoft.com/v1.0/groups/group-id/members?$skiptoken={expectedSkipToken}" : null;
        var expectedUsers = new UserResponse
        {
            Users = [new User { OId = "user-123", DisplayName = "John Doe" }],
            NextLink = nextLink
        };
        _mockGraphGroupApi.GetUsersByGroupIdAsync(groupId, inputToken).Returns(expectedUsers);

        // Act
        var result = await _service.GetGroupMembersAsync(groupId.ToString(), inputToken);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result, Is.Not.Null);
            Assert.That(result.Users, Has.Count.EqualTo(1));
            Assert.That(result.Users[0].OId, Is.EqualTo("user-123"));
            Assert.That(result.SkipToken, Is.EqualTo(expectedSkipToken));
        }
        await _mockGraphGroupApi.Received(1).GetUsersByGroupIdAsync(groupId, inputToken);
    }

    [TestCase("not-a-guid")]
    [TestCase("00000000-0000-0000-0000-000000000000")]
    public async Task GetGroupMembersAsync_WithInvalidOrEmptyGuid_ReturnsEmptyResponse(string groupId)
    {
        // Act
        var result = await _service.GetGroupMembersAsync(groupId, null);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result, Is.Not.Null);
            Assert.That(result.Users, Is.Empty);
        }
        await _mockGraphGroupApi.DidNotReceive().GetUsersByGroupIdAsync(Arg.Any<Guid>(), Arg.Any<string>());
    }

    [Test]
    public async Task GetGroupMembersAsync_WithSinglePage_ReturnsAllUsers()
    {
        // Arrange
        var groupId = Guid.NewGuid();
        var users = new List<User>
        {
            new() { OId = "user-1", DisplayName = "User 1" },
            new() { OId = "user-2", DisplayName = "User 2" }
        };
        var userResponse = new UserResponse
        {
            Users = users,
            NextLink = null
        };
        _mockGraphGroupApi.GetUsersByGroupIdAsync(groupId, null).Returns(userResponse);

        // Act
        var result = await _service.GetGroupMembersAsync(groupId.ToString());

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result, Is.Not.Null);
            Assert.That(result, Has.Count.EqualTo(2));
            Assert.That(result.Select(u => u.OId), Is.EquivalentTo(new List<string> { "user-1", "user-2" }));
        }
        await _mockGraphGroupApi.Received(1).GetUsersByGroupIdAsync(groupId, null);
    }

    [Test]
    public async Task GetGroupMembersAsync_WithMultiplePages_ReturnsAllUsersFromAllPages()
    {
        // Arrange
        var groupId = Guid.NewGuid();

        var firstPageResponse = new UserResponse
        {
            Users = [new() { OId = "user-1", DisplayName = "User 1" }, new() { OId = "user-2", DisplayName = "User 2" }],
            NextLink = $"https://graph.microsoft.com/v1.0/groups/{groupId}/members?$skiptoken=page2token"
        };
        var secondPageResponse = new UserResponse
        {
            Users = [new() { OId = "user-3", DisplayName = "User 3" }, new() { OId = "user-4", DisplayName = "User 4" }],
            NextLink = $"https://graph.microsoft.com/v1.0/groups/{groupId}/members?$skiptoken=page3token"
        };
        var thirdPageResponse = new UserResponse
        {
            Users = [new() { OId = "user-5", DisplayName = "User 5" }],
            NextLink = null
        };

        _mockGraphGroupApi.GetUsersByGroupIdAsync(groupId, null).Returns(firstPageResponse);
        _mockGraphGroupApi.GetUsersByGroupIdAsync(groupId, "page2token").Returns(secondPageResponse);
        _mockGraphGroupApi.GetUsersByGroupIdAsync(groupId, "page3token").Returns(thirdPageResponse);

        // Act
        var result = await _service.GetGroupMembersAsync(groupId.ToString());

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result, Is.Not.Null);
            Assert.That(result, Has.Count.EqualTo(5));
            Assert.That(result.Select(u => u.OId), Is.EquivalentTo(new List<string> { "user-1", "user-2", "user-3", "user-4", "user-5" }));
        }
        await _mockGraphGroupApi.Received(1).GetUsersByGroupIdAsync(groupId, null);
        await _mockGraphGroupApi.Received(1).GetUsersByGroupIdAsync(groupId, "page2token");
        await _mockGraphGroupApi.Received(1).GetUsersByGroupIdAsync(groupId, "page3token");
    }

    [TestCase("not-a-guid")]
    [TestCase("00000000-0000-0000-0000-000000000000")]
    public async Task GetGroupMembersAsync_WithInvalidOrEmptyGuid_ReturnsEmptyList(string groupId)
    {
        // Act
        var result = await _service.GetGroupMembersAsync(groupId);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result, Is.Not.Null);
            Assert.That(result, Is.Empty);
        }
        await _mockGraphGroupApi.DidNotReceive().GetUsersByGroupIdAsync(Arg.Any<Guid>(), Arg.Any<string>());
    }

    [Test]
    public async Task GetGroupMembersAsync_WithNullUsersInResponse_ReturnsEmptyList()
    {
        // Arrange
        var groupId = Guid.NewGuid();
        var userResponse = new UserResponse
        {
            Users = null!,
            NextLink = null
        };
        _mockGraphGroupApi.GetUsersByGroupIdAsync(groupId, null).Returns(userResponse);

        // Act
        var result = await _service.GetGroupMembersAsync(groupId.ToString());

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result, Is.Not.Null);
            Assert.That(result, Is.Empty);
        }
        await _mockGraphGroupApi.Received(1).GetUsersByGroupIdAsync(groupId, null);
    }

    [TestCase(null, null)]
    [TestCase("currentToken", "nextPageToken")]
    public async Task GetGroupsByDisplayNameAsync_WithSearchString_ReturnsGroupsWithSkipToken(string? inputToken, string? expectedSkipToken)
    {
        // Arrange
        var searchString = "Test Group";
        var nextLink = expectedSkipToken != null ? $"https://graph.microsoft.com/v1.0/groups?$search=\"displayName:Test Group\"&$skiptoken={expectedSkipToken}" : null;
        var expectedGroups = new GroupResponse
        {
            Groups = [new Group { Id = Guid.NewGuid().ToString(), DisplayName = "Test Group" }],
            NextLink = nextLink
        };
        _mockGraphGroupApi.SearchGroupsByDisplayNameAsync(searchString, inputToken).Returns(expectedGroups);

        // Act
        var result = await _service.GetGroupsByDisplayNameAsync(searchString, inputToken);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result, Is.Not.Null);
            Assert.That(result.Groups, Has.Count.EqualTo(1));
            Assert.That(result.Groups[0].DisplayName, Is.EqualTo("Test Group"));
            Assert.That(result.SkipToken, Is.EqualTo(expectedSkipToken));
        }
        await _mockGraphGroupApi.Received(1).SearchGroupsByDisplayNameAsync(searchString, inputToken);
    }

    [Test]
    public async Task GetGroupsByDisplayNameAsync_WithEmptySearchString_CallsApiAndReturnsEmptyResult()
    {
        // Arrange
        var searchString = "";
        var expectedGroups = new GroupResponse
        {
            Groups = [],
            NextLink = null
        };
        _mockGraphGroupApi.SearchGroupsByDisplayNameAsync(searchString, null).Returns(expectedGroups);

        // Act
        var result = await _service.GetGroupsByDisplayNameAsync(searchString, null);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result, Is.Not.Null);
            Assert.That(result.Groups, Is.Empty);
        }
        await _mockGraphGroupApi.Received(1).SearchGroupsByDisplayNameAsync(searchString, null);
    }

    [Test]
    public async Task GetGroupsByDisplayNameAsync_WithMultipleResults_ReturnsAllGroups()
    {
        // Arrange
        var searchString = "Group";
        var expectedGroups = new GroupResponse
        {
            Groups = [
                new Group { Id = Guid.NewGuid().ToString(), DisplayName = "Group 1" },
                new Group { Id = Guid.NewGuid().ToString(), DisplayName = "Group 2" },
                new Group { Id = Guid.NewGuid().ToString(), DisplayName = "Group 3" }
           ],
            NextLink = null
        };
        _mockGraphGroupApi.SearchGroupsByDisplayNameAsync(searchString, null).Returns(expectedGroups);

        // Act
        var result = await _service.GetGroupsByDisplayNameAsync(searchString, null);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result, Is.Not.Null);
            Assert.That(result.Groups, Has.Count.EqualTo(3));
            Assert.That(result.Groups.Select(g => g.DisplayName), Is.EquivalentTo(new List<string> { "Group 1", "Group 2", "Group 3" }));
        }
        await _mockGraphGroupApi.Received(1).SearchGroupsByDisplayNameAsync(searchString, null);
    }
}
