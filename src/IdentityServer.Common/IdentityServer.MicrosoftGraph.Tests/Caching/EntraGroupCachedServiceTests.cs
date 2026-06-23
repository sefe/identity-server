// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

using NSubstitute;
using IdentityServer.Abstraction.Configs;
using IdentityServer.Abstraction.Contracts;
using IdentityServer.Abstraction.Contracts.MicrosoftGraph;
using IdentityServer.Abstraction.Entities.EntraEntities;
using IdentityServer.MicrosoftGraph.Caching;

namespace IdentityServer.MicrosoftGraph.Tests.Caching;

[TestFixture]
public class EntraGroupCachedServiceTests
{
    private const string _membershipCacheKeyPrefix = "group-members:";

    // Shared group id constants
    private const string _groupId1 = "group-1";
    private const string _groupId2 = "group-2";
    private const string _groupId3 = "group-3";
    private const string _groupIdEmpty = "group-empty";

    // Shared user id constants
    private const string _userId1 = "user-1";
    private const string _userId2 = "user-2";
    private const string _userId3 = "user-3";

    // Shared search constants
    private const string _searchGroup = "Test Group";

    private static string BuildMembershipKey(string groupId) => $"{_membershipCacheKeyPrefix}{groupId}";

    private IEntraGroupService _mockInnerService;
    private ICache<Group> _mockGroupCache;
    private ICache<User> _mockUserCache;
    private ICache<GroupMembersList> _mockMembershipCache;
    private IMicrosoftEntraCacheConfig _mockCacheConfig;
    private EntraGroupCachedService _service;

    [SetUp]
    public void SetUp()
    {
        _mockInnerService = Substitute.For<IEntraGroupService>();
        _mockGroupCache = Substitute.For<ICache<Group>>();
        _mockUserCache = Substitute.For<ICache<User>>();
        _mockMembershipCache = Substitute.For<ICache<GroupMembersList>>();
        _mockCacheConfig = Substitute.For<IMicrosoftEntraCacheConfig>();

        // Default cache expiration setup
        _mockCacheConfig.GroupExpiration.Returns(TimeSpan.FromMinutes(30));
        _mockCacheConfig.UserExpiration.Returns(TimeSpan.FromMinutes(15));

        _service = new EntraGroupCachedService(
            _mockInnerService,
            _mockGroupCache,
            _mockUserCache,
            _mockMembershipCache,
            _mockCacheConfig);
    }

    #region GetGroupByObjectIdAsync Tests

    [Test]
    public async Task GetGroupByObjectIdAsync_WithCachedGroup_ReturnsFromCache()
    {
        // Arrange
        var groupId = _groupId1;
        var cachedGroup = new Group
        {
            Id = groupId,
            DisplayName = "Cached Group"
        };

        _mockGroupCache.GetOrAddAsync(
            groupId,
            Arg.Any<TimeSpan>(),
            Arg.Any<Func<Task<Group>>>())
            .Returns(cachedGroup);

        // Act
        var result = await _service.GetGroupByObjectIdAsync(groupId);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result, Is.Not.Null);
            Assert.That(result.Groups, Has.Count.EqualTo(1));
            Assert.That(result.Groups[0].Id, Is.EqualTo(groupId));
            Assert.That(result.Groups[0].DisplayName, Is.EqualTo("Cached Group"));
        }

        await _mockGroupCache.Received(1).GetOrAddAsync(
            groupId,
            _mockCacheConfig.GroupExpiration,
            Arg.Any<Func<Task<Group>>>());
    }

    [Test]
    public async Task GetGroupByObjectIdAsync_WithNonCachedGroup_FetchesFromInnerService()
    {
        // Arrange
        var groupId = _groupId2;
        var group = new Group
        {
            Id = groupId,
            DisplayName = "New Group"
        };

        var innerResponse = new GroupResponse();
        innerResponse.Groups.Add(group);

        _mockInnerService.GetGroupByObjectIdAsync(groupId).Returns(innerResponse);

        _mockGroupCache.GetOrAddAsync(
            groupId,
            Arg.Any<TimeSpan>(),
            Arg.Any<Func<Task<Group>>>())
            .Returns(callInfo =>
            {
                var factory = callInfo.ArgAt<Func<Task<Group>>>(2);
                return factory();
            });

        // Act
        var result = await _service.GetGroupByObjectIdAsync(groupId);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result, Is.Not.Null);
            Assert.That(result.Groups, Has.Count.EqualTo(1));
            Assert.That(result.Groups[0].Id, Is.EqualTo(groupId));
            Assert.That(result.Groups[0].DisplayName, Is.EqualTo("New Group"));
        }

        await _mockInnerService.Received(1).GetGroupByObjectIdAsync(groupId);
        await _mockGroupCache.Received(1).GetOrAddAsync(
            groupId,
            _mockCacheConfig.GroupExpiration,
            Arg.Any<Func<Task<Group>>>());
    }

    [Test]
    public async Task GetGroupByObjectIdAsync_WithNullGroup_ReturnsEmptyResponse()
    {
        // Arrange
        var groupId = "non-existent-group";

        _mockGroupCache.GetOrAddAsync(
            groupId,
            Arg.Any<TimeSpan>(),
            Arg.Any<Func<Task<Group>>>())
            .Returns((Group)null!);

        // Act
        var result = await _service.GetGroupByObjectIdAsync(groupId);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result, Is.Not.Null);
            Assert.That(result.Groups, Is.Empty);
        }
    }

    [Test]
    public async Task GetGroupByObjectIdAsync_UsesCorrectCacheExpiration()
    {
        // Arrange
        var customExpiration = TimeSpan.FromHours(2);
        _mockCacheConfig.GroupExpiration.Returns(customExpiration);

        var groupId = _groupId3;
        var group = new Group
        {
            Id = groupId,
            DisplayName = "Test Group"
        };

        _mockGroupCache.GetOrAddAsync(
            groupId,
            Arg.Any<TimeSpan>(),
            Arg.Any<Func<Task<Group>>>())
            .Returns(group);

        // Act
        await _service.GetGroupByObjectIdAsync(groupId);

        // Assert
        await _mockGroupCache.Received(1).GetOrAddAsync(
            groupId,
            customExpiration,
            Arg.Any<Func<Task<Group>>>());
    }

    #endregion

    #region GetGroupsByObjectIdsAsync Tests

    [Test]
    public async Task GetGroupsByObjectIdsAsync_WithEmptyList_ReturnsEmptyResponse()
    {
        // Arrange
        var emptyList = new List<string>();

        // Act
        var result = await _service.GetGroupsByObjectIdsAsync(emptyList);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result, Is.Not.Null);
            Assert.That(result.Groups, Is.Empty);
        }

        await _mockGroupCache.DidNotReceive().GetManyAsync(Arg.Any<IEnumerable<string>>());
        await _mockInnerService.DidNotReceive().GetGroupsByObjectIdsAsync(Arg.Any<IEnumerable<string>>());
    }

    [Test]
    public async Task GetGroupsByObjectIdsAsync_WithAllCachedGroups_ReturnsFromCache()
    {
        // Arrange
        var groupIds = new List<string> { _groupId1, _groupId2, _groupId3 };

        var group1 = new Group { Id = _groupId1, DisplayName = "Group1" };
        var group2 = new Group { Id = _groupId2, DisplayName = "Group2" };
        var group3 = new Group { Id = _groupId3, DisplayName = "Group3" };

        var cachedGroups = new Dictionary<string, Group?>
        {
            { _groupId1, group1 },
            { _groupId2, group2 },
            { _groupId3, group3 }
        };

        _mockGroupCache.GetManyAsync(Arg.Is<IEnumerable<string>>(ids => ids.SequenceEqual(groupIds)))
            .Returns(cachedGroups);

        // Act
        var result = await _service.GetGroupsByObjectIdsAsync(groupIds);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result, Is.Not.Null);
            Assert.That(result.Groups, Has.Count.EqualTo(3));
            Assert.That(result.Groups.Select(g => g.Id), Is.EquivalentTo(groupIds));
        }

        await _mockGroupCache.Received(1).GetManyAsync(Arg.Is<IEnumerable<string>>(ids => ids.SequenceEqual(groupIds)));
        await _mockInnerService.DidNotReceive().GetGroupsByObjectIdsAsync(Arg.Any<IEnumerable<string>>());
        await _mockGroupCache.DidNotReceive().SetManyAsync(Arg.Any<Dictionary<string, Group>>(), Arg.Any<TimeSpan>());
    }

    [Test]
    public async Task GetGroupsByObjectIdsAsync_WithPartialCacheHit_FetchesMissingGroups()
    {
        // Arrange
        var groupIds = new List<string> { _groupId1, _groupId2, _groupId3 };

        var group1 = new Group { Id = _groupId1, DisplayName = "Group1" };
        var group3 = new Group { Id = _groupId3, DisplayName = "Group3" };

        var cachedGroups = new Dictionary<string, Group?>
        {
            { _groupId1, group1 },
            { _groupId2, null },
            { _groupId3, group3 }
        };

        _mockGroupCache.GetManyAsync(Arg.Is<IEnumerable<string>>(ids => ids.SequenceEqual(groupIds)))
            .Returns(cachedGroups);

        var group2 = new Group { Id = _groupId2, DisplayName = "Group2" };
        var fetchedResponse = new GroupResponse();
        fetchedResponse.Groups.Add(group2);

        _mockInnerService.GetGroupsByObjectIdsAsync(Arg.Is<IEnumerable<string>>(ids => ids.Contains(_groupId2)))
            .Returns(fetchedResponse);

        // Act
        var result = await _service.GetGroupsByObjectIdsAsync(groupIds);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result, Is.Not.Null);
            Assert.That(result.Groups, Has.Count.EqualTo(3));
            Assert.That(result.Groups.Select(g => g.Id), Is.EquivalentTo(groupIds));
        }

        await _mockGroupCache.Received(1).GetManyAsync(Arg.Is<IEnumerable<string>>(ids => ids.SequenceEqual(groupIds)));
        await _mockInnerService.Received(1).GetGroupsByObjectIdsAsync(
            Arg.Is<IEnumerable<string>>(ids => ids.SequenceEqual(new[] { _groupId2 })));
        await _mockGroupCache.Received(1).SetManyAsync(
            Arg.Is<Dictionary<string, Group>>(dict => dict.ContainsKey(_groupId2) && dict[_groupId2] == group2),
            _mockCacheConfig.GroupExpiration);
    }

    [Test]
    public async Task GetGroupsByObjectIdsAsync_WithAllCacheMisses_FetchesAllFromInnerService()
    {
        // Arrange
        var groupIds = new List<string> { _groupId1, _groupId2 };

        var cachedGroups = new Dictionary<string, Group?>
        {
            { _groupId1, null },
            { _groupId2, null }
        };

        _mockGroupCache.GetManyAsync(Arg.Is<IEnumerable<string>>(ids => ids.SequenceEqual(groupIds)))
            .Returns(cachedGroups);

        var group1 = new Group { Id = _groupId1, DisplayName = "Group1" };
        var group2 = new Group { Id = _groupId2, DisplayName = "Group2" };
        var fetchedResponse = new GroupResponse();
        fetchedResponse.Groups.Add(group1);
        fetchedResponse.Groups.Add(group2);

        _mockInnerService.GetGroupsByObjectIdsAsync(Arg.Is<IEnumerable<string>>(ids => ids.SequenceEqual(groupIds)))
            .Returns(fetchedResponse);

        // Act
        var result = await _service.GetGroupsByObjectIdsAsync(groupIds);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result, Is.Not.Null);
            Assert.That(result.Groups, Has.Count.EqualTo(2));
            Assert.That(result.Groups.Select(g => g.Id), Is.EquivalentTo(groupIds));
        }

        await _mockGroupCache.Received(1).GetManyAsync(Arg.Is<IEnumerable<string>>(ids => ids.SequenceEqual(groupIds)));
        await _mockInnerService.Received(1).GetGroupsByObjectIdsAsync(Arg.Is<IEnumerable<string>>(ids => ids.SequenceEqual(groupIds)));
        await _mockGroupCache.Received(1).SetManyAsync(
            Arg.Is<Dictionary<string, Group>>(dict =>
                dict.Count == 2 &&
                dict.ContainsKey(_groupId1) &&
                dict.ContainsKey(_groupId2)),
            _mockCacheConfig.GroupExpiration);
    }

    [Test]
    public async Task GetGroupsByObjectIdsAsync_WithNoFetchedResults_DoesNotCacheEmptyResults()
    {
        // Arrange
        var groupIds = new List<string> { _groupId1 };

        var cachedGroups = new Dictionary<string, Group?>
        {
            { _groupId1, null }
        };

        _mockGroupCache.GetManyAsync(Arg.Is<IEnumerable<string>>(ids => ids.SequenceEqual(groupIds)))
            .Returns(cachedGroups);

        var emptyResponse = new GroupResponse();
        _mockInnerService.GetGroupsByObjectIdsAsync(Arg.Is<IEnumerable<string>>(ids => ids.SequenceEqual(groupIds)))
            .Returns(emptyResponse);

        // Act
        var result = await _service.GetGroupsByObjectIdsAsync(groupIds);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result, Is.Not.Null);
            Assert.That(result.Groups, Is.Empty);
        }

        await _mockGroupCache.DidNotReceive().SetManyAsync(Arg.Any<Dictionary<string, Group>>(), Arg.Any<TimeSpan>());
    }

    #endregion

    #region GetGroupMembersAsync (with skipToken) Tests

    [Test]
    public async Task GetGroupMembersAsync_WithSkipToken_BypassesCache()
    {
        // Arrange
        var skipToken = "skip-token-xyz";
        var groupId = _groupId1;

        var user1 = new User { OId = _userId1, DisplayName = "User1" };
        var user2 = new User { OId = _userId2, DisplayName = "User2" };

        var expectedResponse = new UserResponse();
        expectedResponse.Users.Add(user1);
        expectedResponse.Users.Add(user2);

        _mockInnerService.GetGroupMembersAsync(groupId, skipToken).Returns(expectedResponse);

        // Act
        var result = await _service.GetGroupMembersAsync(groupId, skipToken);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result, Is.Not.Null);
            Assert.That(result.Users, Has.Count.EqualTo(2));
        }

        await _mockInnerService.Received(1).GetGroupMembersAsync(groupId, skipToken);
        await _mockMembershipCache.DidNotReceive().GetAsync(Arg.Any<string>());
        await _mockUserCache.DidNotReceive().GetManyAsync(Arg.Any<IEnumerable<string>>());
    }

    [Test]
    public async Task GetGroupMembersAsync_WithNullSkipToken_BypassesCache()
    {
        // Arrange
        var groupId = _groupId1;

        var user1 = new User { OId = _userId1, DisplayName = "User1" };
        var expectedResponse = new UserResponse();
        expectedResponse.Users.Add(user1);

        _mockInnerService.GetGroupMembersAsync(groupId, null).Returns(expectedResponse);

        // Act
        var result = await _service.GetGroupMembersAsync(groupId, null);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result, Is.Not.Null);
            Assert.That(result.Users, Has.Count.EqualTo(1));
        }

        await _mockInnerService.Received(1).GetGroupMembersAsync(groupId, null);
    }

    #endregion

    #region GetGroupMembersAsync (no skipToken) Tests

    [Test]
    public async Task GetGroupMembersAsync_WithCachedMembership_ReturnsFromCache()
    {
        // Arrange
        var groupId = _groupId1;
        var membershipCacheKey = BuildMembershipKey(groupId);

        var user1 = new User { OId = _userId1, DisplayName = "User1" };
        var user2 = new User { OId = _userId2, DisplayName = "User2" };

        var cachedUserIds = new GroupMembersList { _userId1, _userId2 };
        var cachedUsers = new Dictionary<string, User?>
        {
            { _userId1, user1 },
            { _userId2, user2 }
        };

        _mockMembershipCache.GetAsync(membershipCacheKey).Returns(cachedUserIds);
        _mockUserCache.GetManyAsync(Arg.Is<IEnumerable<string>>(ids => ids.SequenceEqual(cachedUserIds)))
            .Returns(cachedUsers);

        // Act
        var result = await _service.GetGroupMembersAsync(groupId);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result, Has.Count.EqualTo(2));
            Assert.That(result.Select(u => u.OId), Is.EquivalentTo(new[] { _userId1, _userId2 }));
        }

        await _mockMembershipCache.Received(1).GetAsync(membershipCacheKey);
        await _mockUserCache.Received(1).GetManyAsync(Arg.Is<IEnumerable<string>>(ids => ids.SequenceEqual(cachedUserIds)));
        await _mockInnerService.DidNotReceive().GetGroupMembersAsync(groupId);
    }

    [Test]
    public async Task GetGroupMembersAsync_WithIncompleteCachedUsers_FetchesFromInnerService()
    {
        // Arrange
        var groupId = _groupId1;
        var membershipCacheKey = BuildMembershipKey(groupId);

        var user1 = new User { OId = _userId1, DisplayName = "User1" };

        var cachedUserIds = new GroupMembersList { _userId1, _userId2 };
        var cachedUsers = new Dictionary<string, User?>
        {
            { _userId1, user1 },
            { _userId2, null } // Missing user in cache
        };

        _mockMembershipCache.GetAsync(membershipCacheKey).Returns(cachedUserIds);
        _mockUserCache.GetManyAsync(Arg.Is<IEnumerable<string>>(ids => ids.SequenceEqual(cachedUserIds)))
            .Returns(cachedUsers);

        var user2 = new User { OId = _userId2, DisplayName = "User2" };
        var fetchedUsers = new List<User> { user1, user2 };

        _mockInnerService.GetGroupMembersAsync(groupId).Returns(fetchedUsers);

        // Act
        var result = await _service.GetGroupMembersAsync(groupId);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result, Has.Count.EqualTo(2));
            Assert.That(result.Select(u => u.OId), Is.EquivalentTo(new[] { _userId1, _userId2 }));
        }

        await _mockInnerService.Received(1).GetGroupMembersAsync(groupId);
        await _mockUserCache.Received(1).SetManyAsync(
            Arg.Is<Dictionary<string, User>>(dict =>
                dict.Count == 2 &&
                dict.ContainsKey(_userId1) &&
                dict.ContainsKey(_userId2)),
            _mockCacheConfig.UserExpiration);
    }

    [Test]
    public async Task GetGroupMembersAsync_WithNoCachedMembership_FetchesFromInnerService()
    {
        // Arrange
        var groupId = _groupId1;
        var membershipCacheKey = BuildMembershipKey(groupId);

        _mockMembershipCache.GetAsync(membershipCacheKey).Returns((GroupMembersList?)null);

        var user1 = new User { OId = _userId1, DisplayName = "User1" };
        var user2 = new User { OId = _userId2, DisplayName = "User2" };
        var fetchedUsers = new List<User> { user1, user2 };

        _mockInnerService.GetGroupMembersAsync(groupId).Returns(fetchedUsers);

        // Act
        var result = await _service.GetGroupMembersAsync(groupId);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result, Has.Count.EqualTo(2));
            Assert.That(result.Select(u => u.OId), Is.EquivalentTo(new[] { _userId1, _userId2 }));
        }

        await _mockInnerService.Received(1).GetGroupMembersAsync(groupId);
    }

    [Test]
    public async Task GetGroupMembersAsync_AfterFetch_CachesUsersAndMembership()
    {
        // Arrange
        var groupId = _groupId1;
        var membershipCacheKey = BuildMembershipKey(groupId);

        _mockMembershipCache.GetAsync(membershipCacheKey).Returns((GroupMembersList?)null);

        var user1 = new User { OId = _userId1, DisplayName = "User1" };
        var user2 = new User { OId = _userId2, DisplayName = "User2" };
        var fetchedUsers = new List<User> { user1, user2 };

        _mockInnerService.GetGroupMembersAsync(groupId).Returns(fetchedUsers);

        // Act
        var result = await _service.GetGroupMembersAsync(groupId);

        // Assert
        Assert.That(result, Has.Count.EqualTo(2));

        await _mockUserCache.Received(1).SetManyAsync(
            Arg.Is<Dictionary<string, User>>(dict =>
                dict.Count == 2 &&
                dict[_userId1] == user1 &&
                dict[_userId2] == user2),
            _mockCacheConfig.UserExpiration);

        await _mockMembershipCache.Received(1).SetAsync(
            membershipCacheKey,
            Arg.Is<GroupMembersList>(list =>
                list.Count == 2 &&
                list.Contains(_userId1) &&
                list.Contains(_userId2)),
            _mockCacheConfig.UserExpiration);
    }

    [Test]
    public async Task GetGroupMembersAsync_WithEmptyResult_DoesNotCache()
    {
        // Arrange
        var groupId = _groupIdEmpty;
        var membershipCacheKey = BuildMembershipKey(groupId);

        _mockMembershipCache.GetAsync(membershipCacheKey).Returns((GroupMembersList?)null);
        _mockInnerService.GetGroupMembersAsync(groupId).Returns(new List<User>());

        // Act
        var result = await _service.GetGroupMembersAsync(groupId);

        // Assert
        Assert.That(result, Is.Empty);

        await _mockUserCache.DidNotReceive().SetManyAsync(Arg.Any<Dictionary<string, User>>(), Arg.Any<TimeSpan>());
        await _mockMembershipCache.DidNotReceive().SetAsync(Arg.Any<string>(), Arg.Any<GroupMembersList>(), Arg.Any<TimeSpan>());
    }

    [Test]
    public async Task GetGroupMembersAsync_WithEmptyCachedMembership_FetchesFromInnerService()
    {
        // Arrange
        var groupId = _groupId1;
        var membershipCacheKey = BuildMembershipKey(groupId);

        var emptyMembershipList = new GroupMembersList();
        _mockMembershipCache.GetAsync(membershipCacheKey).Returns(emptyMembershipList);

        var user1 = new User { OId = _userId1, DisplayName = "User1" };
        var fetchedUsers = new List<User> { user1 };

        _mockInnerService.GetGroupMembersAsync(groupId).Returns(fetchedUsers);

        // Act
        var result = await _service.GetGroupMembersAsync(groupId);

        // Assert
        Assert.That(result, Has.Count.EqualTo(1));

        await _mockInnerService.Received(1).GetGroupMembersAsync(groupId);
    }

    [Test]
    public async Task GetGroupMembersAsync_UsesCorrectUserCacheExpiration()
    {
        // Arrange
        var customExpiration = TimeSpan.FromMinutes(45);
        _mockCacheConfig.UserExpiration.Returns(customExpiration);

        var groupId = _groupId1;
        var membershipCacheKey = BuildMembershipKey(groupId);

        _mockMembershipCache.GetAsync(membershipCacheKey).Returns((GroupMembersList?)null);

        var user1 = new User { OId = _userId1, DisplayName = "User1" };
        var fetchedUsers = new List<User> { user1 };

        _mockInnerService.GetGroupMembersAsync(groupId).Returns(fetchedUsers);

        // Act
        await _service.GetGroupMembersAsync(groupId);

        // Assert
        await _mockUserCache.Received(1).SetManyAsync(
            Arg.Any<Dictionary<string, User>>(),
            customExpiration);

        await _mockMembershipCache.Received(1).SetAsync(
            Arg.Any<string>(),
            Arg.Any<GroupMembersList>(),
            customExpiration);
    }

    #endregion

    #region GetGroupsByDisplayNameAsync Tests

    [Test]
    public async Task GetGroupsByDisplayNameAsync_WithSearchString_BypassesCache()
    {
        // Arrange
        var skipToken = "skip-123";
        var searchString = _searchGroup;

        var group1 = new Group { Id = _groupId1, DisplayName = "Test Group1" };
        var expectedResponse = new GroupResponse();
        expectedResponse.Groups.Add(group1);

        _mockInnerService.GetGroupsByDisplayNameAsync(searchString, skipToken).Returns(expectedResponse);

        // Act
        var result = await _service.GetGroupsByDisplayNameAsync(searchString, skipToken);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result, Is.Not.Null);
            Assert.That(result.Groups, Has.Count.EqualTo(1));
        }

        await _mockInnerService.Received(1).GetGroupsByDisplayNameAsync(searchString, skipToken);
        await _mockGroupCache.DidNotReceive().GetAsync(Arg.Any<string>());
        await _mockGroupCache.DidNotReceive().GetManyAsync(Arg.Any<IEnumerable<string>>());
    }

    [Test]
    public async Task GetGroupsByDisplayNameAsync_WithNullSkipToken_BypassesCache()
    {
        // Arrange
        var searchString = _searchGroup;

        var group1 = new Group { Id = _groupId1, DisplayName = "Test Group1" };
        var expectedResponse = new GroupResponse();
        expectedResponse.Groups.Add(group1);

        _mockInnerService.GetGroupsByDisplayNameAsync(searchString, null).Returns(expectedResponse);

        // Act
        var result = await _service.GetGroupsByDisplayNameAsync(searchString, null);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result, Is.Not.Null);
            Assert.That(result.Groups, Has.Count.EqualTo(1));
        }

        await _mockInnerService.Received(1).GetGroupsByDisplayNameAsync(searchString, null);
    }

    #endregion
}
