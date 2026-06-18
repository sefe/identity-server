using NSubstitute;
using System.Security.Cryptography;
using System.Text;
using IdentityServer.Abstraction.Configs;
using IdentityServer.Abstraction.Contracts;
using IdentityServer.Abstraction.Contracts.MicrosoftGraph;
using IdentityServer.Abstraction.Entities.EntraEntities;
using IdentityServer.MicrosoftGraph.Caching;

namespace IdentityServer.MicrosoftGraph.Tests.Caching;

[TestFixture]
public class EntraUserCachedServiceTests
{
    private const string _userId1 = "user-1";
    private const string _userId2 = "user-2";
    private const string _userId3 = "user-3";
    private const string _groupId1 = "group-1";
    private const string _groupId2 = "group-2";
    private const string _groupId3 = "group-3";

    // Cache key prefixes matching production code
    private const string _cacheKeyPrefixUserFilteredGroups = "user-filtered-groups:";
    private const string _cacheKeyPrefixUserOnPremProps = "user-onprem-props:";
    private const string _cacheKeyPrefixUserProps = "user-props:";

    private IEntraUserService _mockInnerService;
    private ICache<User> _mockUserCache;
    private ICache<Group> _mockGroupCache;
    private ICache<UserMembershipInGroupList> _mockMembershipCache;
    private ICache<UserPropertiesDictionary> _mockPropertiesCache;
    private IMicrosoftEntraCacheConfig _mockCacheConfig;
    private EntraUserCachedService _service;

    [SetUp]
    public void SetUp()
    {
        _mockInnerService = Substitute.For<IEntraUserService>();
        _mockUserCache = Substitute.For<ICache<User>>();
        _mockGroupCache = Substitute.For<ICache<Group>>();
        _mockMembershipCache = Substitute.For<ICache<UserMembershipInGroupList>>();
        _mockPropertiesCache = Substitute.For<ICache<UserPropertiesDictionary>>();
        _mockCacheConfig = Substitute.For<IMicrosoftEntraCacheConfig>();

        _mockCacheConfig.UserExpiration.Returns(TimeSpan.FromMinutes(15));

        _service = new EntraUserCachedService(
            _mockInnerService,
            _mockUserCache,
            _mockGroupCache,
            _mockMembershipCache,
            _mockPropertiesCache,
            _mockCacheConfig);
    }

    #region GetUsersByDisplayNameAsync Tests

    [Test]
    public async Task GetUsersByDisplayNameAsync_AlwaysCallsInnerService_DoesNotCache()
    {
        // Arrange
        var searchString = "John";
        var searchResponse = new UserResponse();
        searchResponse.Users.Add(new User { OId = _userId1, DisplayName = "John Doe" });

        _mockInnerService.GetUsersByDisplayNameAsync(searchString).Returns(searchResponse);

        // Act
        var result1 = await _service.GetUsersByDisplayNameAsync(searchString);
        var result2 = await _service.GetUsersByDisplayNameAsync(searchString);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result1, Is.Not.Null);
            Assert.That(result1.Users, Has.Count.EqualTo(1));
            Assert.That(result2, Is.Not.Null);
            Assert.That(result2.Users, Has.Count.EqualTo(1));
        }

        await _mockInnerService.Received(2).GetUsersByDisplayNameAsync(searchString);
        await _mockUserCache.DidNotReceive().GetOrAddAsync(
            Arg.Any<string>(),
            Arg.Any<TimeSpan>(),
            Arg.Any<Func<Task<User>>>());
    }

    #endregion

    #region GetUserByObjectIdAsync Tests

    [Test]
    public async Task GetUserByObjectIdAsync_WithCachedUser_ReturnsFromCache()
    {
        // Arrange
        var userId = _userId1;
        var cachedUser = new User { OId = userId, DisplayName = "Cached User" };

        _mockUserCache.GetOrAddAsync(
                userId,
                Arg.Any<TimeSpan>(),
                Arg.Any<Func<Task<User>>>())
            .Returns(cachedUser);

        // Act
        var result = await _service.GetUserByObjectIdAsync(userId);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result, Is.Not.Null);
            Assert.That(result.Users, Has.Count.EqualTo(1));
            Assert.That(result.Users[0].OId, Is.EqualTo(userId));
            Assert.That(result.Users[0].DisplayName, Is.EqualTo("Cached User"));
        }

        await _mockUserCache.Received(1).GetOrAddAsync(
            userId,
            _mockCacheConfig.UserExpiration,
            Arg.Any<Func<Task<User>>>());
    }

    [Test]
    public async Task GetUserByObjectIdAsync_WithNonCachedUser_FetchesFromInnerService()
    {
        // Arrange
        var userId = _userId2;
        var user = new User { OId = userId, DisplayName = "New User" };
        var innerResponse = new UserResponse();
        innerResponse.Users.Add(user);

        _mockInnerService.GetUserByObjectIdAsync(userId).Returns(innerResponse);

        _mockUserCache.GetOrAddAsync(
                userId,
                Arg.Any<TimeSpan>(),
                Arg.Any<Func<Task<User>>>())
            .Returns(callInfo =>
            {
                var factory = callInfo.ArgAt<Func<Task<User>>>(2);
                return factory();
            });

        // Act
        var result = await _service.GetUserByObjectIdAsync(userId);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result, Is.Not.Null);
            Assert.That(result.Users, Has.Count.EqualTo(1));
            Assert.That(result.Users[0].OId, Is.EqualTo(userId));
            Assert.That(result.Users[0].DisplayName, Is.EqualTo("New User"));
        }

        await _mockInnerService.Received(1).GetUserByObjectIdAsync(userId);
        await _mockUserCache.Received(1).GetOrAddAsync(
            userId,
            _mockCacheConfig.UserExpiration,
            Arg.Any<Func<Task<User>>>());
    }

    [Test]
    public async Task GetUserByObjectIdAsync_WithNullUser_ReturnsEmptyResponse()
    {
        // Arrange
        var userId = "non-existent-user";

        _mockUserCache.GetOrAddAsync(
                userId,
                Arg.Any<TimeSpan>(),
                Arg.Any<Func<Task<User>>>())
            .Returns((User)null!);

        // Act
        var result = await _service.GetUserByObjectIdAsync(userId);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result, Is.Not.Null);
            Assert.That(result.Users, Is.Empty);
        }
    }

    [Test]
    public async Task GetUserByObjectIdAsync_UsesCorrectCacheExpiration()
    {
        // Arrange
        var customExpiration = TimeSpan.FromHours(2);
        _mockCacheConfig.UserExpiration.Returns(customExpiration);

        var userId = _userId3;
        var user = new User { OId = userId, DisplayName = "Test User" };

        _mockUserCache.GetOrAddAsync(
                userId,
                Arg.Any<TimeSpan>(),
                Arg.Any<Func<Task<User>>>())
            .Returns(user);

        // Act
        await _service.GetUserByObjectIdAsync(userId);

        // Assert
        await _mockUserCache.Received(1).GetOrAddAsync(
            userId,
            customExpiration,
            Arg.Any<Func<Task<User>>>());
    }

    #endregion

    #region GetUsersByObjectIdsAsync Tests

    [Test]
    public async Task GetUsersByObjectIdsAsync_WithEmptyList_ReturnsEmptyResponse()
    {
        // Arrange
        var emptyList = new List<string>();

        // Act
        var result = await _service.GetUsersByObjectIdsAsync(emptyList);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result, Is.Not.Null);
            Assert.That(result.Users, Is.Empty);
        }

        await _mockUserCache.DidNotReceive().GetManyAsync(Arg.Any<IEnumerable<string>>());
        await _mockInnerService.DidNotReceive().GetUsersByObjectIdsAsync(Arg.Any<IEnumerable<string>>());
    }

    [Test]
    public async Task GetUsersByObjectIdsAsync_WithAllCachedUsers_ReturnsFromCache()
    {
        // Arrange
        var userIds = new List<string> { _userId1, _userId2, _userId3 };
        var user1 = new User { OId = _userId1, DisplayName = "User1" };
        var user2 = new User { OId = _userId2, DisplayName = "User2" };
        var user3 = new User { OId = _userId3, DisplayName = "User3" };

        var cachedUsers = new Dictionary<string, User?>
        {
            { _userId1, user1 },
            { _userId2, user2 },
            { _userId3, user3 }
        };

        _mockUserCache.GetManyAsync(Arg.Is<IEnumerable<string>>(ids => ids.SequenceEqual(userIds)))
            .Returns(cachedUsers);

        // Act
        var result = await _service.GetUsersByObjectIdsAsync(userIds);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result, Is.Not.Null);
            Assert.That(result.Users, Has.Count.EqualTo(3));
            Assert.That(result.Users.Select(u => u.OId), Is.EquivalentTo(userIds));
        }

        await _mockUserCache.Received(1).GetManyAsync(Arg.Is<IEnumerable<string>>(ids => ids.SequenceEqual(userIds)));
        await _mockInnerService.DidNotReceive().GetUsersByObjectIdsAsync(Arg.Any<IEnumerable<string>>());
        await _mockUserCache.DidNotReceive().SetManyAsync(Arg.Any<Dictionary<string, User>>(), Arg.Any<TimeSpan>());
    }

    [Test]
    public async Task GetUsersByObjectIdsAsync_WithPartialCacheHit_FetchesMissingUsers()
    {
        // Arrange
        var userIds = new List<string> { _userId1, _userId2, _userId3 };
        var user1 = new User { OId = _userId1, DisplayName = "User1" };
        var user3 = new User { OId = _userId3, DisplayName = "User3" };

        var cachedUsers = new Dictionary<string, User?>
        {
            { _userId1, user1 },
            { _userId2, null },
            { _userId3, user3 }
        };

        _mockUserCache.GetManyAsync(Arg.Is<IEnumerable<string>>(ids => ids.SequenceEqual(userIds)))
            .Returns(cachedUsers);

        var user2 = new User { OId = _userId2, DisplayName = "User2" };
        var fetchedResponse = new UserResponse();
        fetchedResponse.Users.Add(user2);

        _mockInnerService.GetUsersByObjectIdsAsync(Arg.Is<IEnumerable<string>>(ids => ids.Contains(_userId2)))
         .Returns(fetchedResponse);

        // Act
        var result = await _service.GetUsersByObjectIdsAsync(userIds);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result.Users, Has.Count.EqualTo(3));
            Assert.That(result.Users.Select(u => u.OId), Is.EquivalentTo(userIds));
        }

        await _mockUserCache.Received(1).GetManyAsync(Arg.Is<IEnumerable<string>>(ids => ids.SequenceEqual(userIds)));
        await _mockInnerService.Received(1).GetUsersByObjectIdsAsync(Arg.Is<IEnumerable<string>>(ids => ids.SequenceEqual(new[] { _userId2 })));
        await _mockUserCache.Received(1).SetManyAsync(
            Arg.Is<Dictionary<string, User>>(dict => dict.ContainsKey(_userId2) && dict[_userId2] == user2),
            _mockCacheConfig.UserExpiration);
    }

    [Test]
    public async Task GetUsersByObjectIdsAsync_WithAllCacheMisses_FetchesAllFromInnerService()
    {
        // Arrange
        var userIds = new List<string> { _userId1, _userId2 };
        var cachedUsers = new Dictionary<string, User?>
        {
            { _userId1, null },
            { _userId2, null }
        };

        _mockUserCache.GetManyAsync(Arg.Is<IEnumerable<string>>(ids => ids.SequenceEqual(userIds)))
            .Returns(cachedUsers);

        var user1 = new User { OId = _userId1, DisplayName = "User1" };
        var user2 = new User { OId = _userId2, DisplayName = "User2" };
        var fetchedResponse = new UserResponse();
        fetchedResponse.Users.Add(user1);
        fetchedResponse.Users.Add(user2);

        _mockInnerService.GetUsersByObjectIdsAsync(Arg.Is<IEnumerable<string>>(ids => ids.SequenceEqual(userIds)))
            .Returns(fetchedResponse);

        // Act
        var result = await _service.GetUsersByObjectIdsAsync(userIds);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result.Users, Has.Count.EqualTo(2));
            Assert.That(result.Users.Select(u => u.OId), Is.EquivalentTo(userIds));
        }

        await _mockUserCache.Received(1).GetManyAsync(Arg.Is<IEnumerable<string>>(ids => ids.SequenceEqual(userIds)));
        await _mockInnerService.Received(1).GetUsersByObjectIdsAsync(Arg.Is<IEnumerable<string>>(ids => ids.SequenceEqual(userIds)));
        await _mockUserCache.Received(1).SetManyAsync(
            Arg.Is<Dictionary<string, User>>(dict =>
                dict.Count == 2 &&
                dict.ContainsKey(_userId1) &&
                dict.ContainsKey(_userId2)),
            _mockCacheConfig.UserExpiration);
    }

    [Test]
    public async Task GetUsersByObjectIdsAsync_WithNoFetchedResults_DoesNotCache()
    {
        // Arrange
        var userIds = new List<string> { _userId1 };
        var cachedUsers = new Dictionary<string, User?> { { _userId1, null } };

        _mockUserCache.GetManyAsync(Arg.Is<IEnumerable<string>>(ids => ids.SequenceEqual(userIds)))
           .Returns(cachedUsers);

        var emptyResponse = new UserResponse();
        _mockInnerService.GetUsersByObjectIdsAsync(Arg.Is<IEnumerable<string>>(ids => ids.SequenceEqual(userIds)))
            .Returns(emptyResponse);

        // Act
        var result = await _service.GetUsersByObjectIdsAsync(userIds);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result.Users, Is.Empty);
        }

        await _mockUserCache.DidNotReceive().SetManyAsync(Arg.Any<Dictionary<string, User>>(), Arg.Any<TimeSpan>());
    }

    #endregion

    #region GetUserMembershipInGroups Tests

    [Test]
    public async Task GetUserMembershipInGroups_WithEmptyFilter_ReturnsEmpty()
    {
        // Arrange
        var emptyFilter = new List<string>();

        // Act
        var result = await _service.GetUserMembershipInGroups(_userId1, emptyFilter);

        // Assert
        Assert.That(result, Is.Empty);

        await _mockMembershipCache.DidNotReceive().GetAsync(Arg.Any<string>());
    }

    [Test]
    public async Task GetUserMembershipInGroups_WithCachedMembershipAndGroups_ReturnsFromCache()
    {
        // Arrange
        var filter = new List<string> { _groupId1, _groupId2 };
        var sorted = string.Join(",", filter.OrderBy(g => g));
        var hash = Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(sorted)))[..16];
        var membershipKey = $"{_cacheKeyPrefixUserFilteredGroups}{_userId1}:{hash}";

        var cachedGroupIds = new UserMembershipInGroupList { _groupId1, _groupId2 };
        var group1 = new Group { Id = _groupId1, DisplayName = "Group1" };
        var group2 = new Group { Id = _groupId2, DisplayName = "Group2" };

        var cachedGroups = new Dictionary<string, Group?>
{
            { _groupId1, group1 },
            { _groupId2, group2 }
        };

        _mockMembershipCache.GetAsync(membershipKey).Returns(cachedGroupIds);
        _mockGroupCache.GetManyAsync(Arg.Is<IEnumerable<string>>(ids => ids.SequenceEqual(cachedGroupIds)))
            .Returns(cachedGroups);

        // Act
        var result = await _service.GetUserMembershipInGroups(_userId1, filter);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result, Has.Count.EqualTo(2));
            Assert.That(result.Select(g => g.Id), Is.EquivalentTo(filter));
        }

        await _mockInnerService.DidNotReceive().GetUserMembershipInGroups(Arg.Any<string>(), Arg.Any<IEnumerable<string>>());
    }

    [Test]
    public async Task GetUserMembershipInGroups_WithCachedMembershipMissingGroups_FetchesFromInnerService()
    {
        // Arrange
        var filter = new List<string> { _groupId1, _groupId2 };
        var sorted = string.Join(",", filter.OrderBy(g => g));
        var hash = Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(sorted)))[..16];
        var membershipKey = $"{_cacheKeyPrefixUserFilteredGroups}{_userId1}:{hash}";

        var cachedGroupIds = new UserMembershipInGroupList { _groupId1, _groupId2 };
        var group1 = new Group { Id = _groupId1 };

        var cachedGroups = new Dictionary<string, Group?>
        {
            { _groupId1, group1 },
            { _groupId2, null }
        };

        _mockMembershipCache.GetAsync(membershipKey).Returns(cachedGroupIds);
        _mockGroupCache.GetManyAsync(Arg.Is<IEnumerable<string>>(ids => ids.SequenceEqual(cachedGroupIds)))
             .Returns(cachedGroups);

        var fetchedGroups = new List<Group> { new() { Id = _groupId1 }, new() { Id = _groupId2 } };
        _mockInnerService.GetUserMembershipInGroups(_userId1, Arg.Is<IEnumerable<string>>(ids => ids.SequenceEqual(filter)))
            .Returns(fetchedGroups);

        // Act
        var result = await _service.GetUserMembershipInGroups(_userId1, filter);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result, Has.Count.EqualTo(2));
            Assert.That(result.Select(g => g.Id), Is.EquivalentTo(filter));
        }

        await _mockInnerService.Received(1).GetUserMembershipInGroups(_userId1, Arg.Is<IEnumerable<string>>(ids => ids.SequenceEqual(filter)));
        await _mockMembershipCache.Received(1).SetAsync(
            membershipKey,
            Arg.Is<UserMembershipInGroupList>(list => list.Count == 2 && list.Contains(_groupId1) && list.Contains(_groupId2)),
            _mockCacheConfig.UserExpiration);
    }

    [Test]
    public async Task GetUserMembershipInGroups_WithNoCachedMembership_FetchesFromInnerServiceAndCachesMembership()
    {
        // Arrange
        var filter = new List<string> { _groupId1 };
        var sorted = string.Join(",", filter.OrderBy(g => g));
        var hash = Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(sorted)))[..16];
        var membershipKey = $"{_cacheKeyPrefixUserFilteredGroups}{_userId1}:{hash}";

        _mockMembershipCache.GetAsync(membershipKey).Returns((UserMembershipInGroupList?)null);

        var fetchedGroups = new List<Group> { new() { Id = _groupId1 } };
        _mockInnerService.GetUserMembershipInGroups(_userId1, Arg.Is<IEnumerable<string>>(ids => ids.SequenceEqual(filter)))
            .Returns(fetchedGroups);

        // Act
        var result = await _service.GetUserMembershipInGroups(_userId1, filter);

        // Assert
        Assert.That(result, Has.Count.EqualTo(1));

        await _mockMembershipCache.Received(1).SetAsync(
            membershipKey,
            Arg.Is<UserMembershipInGroupList>(list => list.Count == 1 && list.Contains(_groupId1)),
            _mockCacheConfig.UserExpiration);
    }

    [Test]
    public async Task GetUserMembershipInGroups_WithEmptyFetchedGroups_DoesNotCacheMembership()
    {
        // Arrange
        var filter = new List<string> { _groupId1 };
        var sorted = string.Join(",", filter.OrderBy(g => g));
        var hash = Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(sorted)))[..16];
        var membershipKey = $"{_cacheKeyPrefixUserFilteredGroups}{_userId1}:{hash}";

        _mockMembershipCache.GetAsync(membershipKey).Returns((UserMembershipInGroupList?)null);
        _mockInnerService.GetUserMembershipInGroups(_userId1, Arg.Is<IEnumerable<string>>(ids => ids.SequenceEqual(filter)))
            .Returns(new List<Group>());

        // Act
        var result = await _service.GetUserMembershipInGroups(_userId1, filter);

        // Assert
        Assert.That(result, Is.Empty);

        await _mockMembershipCache.DidNotReceive().SetAsync(Arg.Any<string>(), Arg.Any<UserMembershipInGroupList>(), Arg.Any<TimeSpan>());
    }

    [Test]
    public async Task GetUserMembershipInGroups_UsesCorrectMembershipCacheExpiration()
    {
        // Arrange
        var customExpiration = TimeSpan.FromMinutes(45);
        _mockCacheConfig.UserExpiration.Returns(customExpiration);

        var filter = new List<string> { _groupId1, _groupId2 };
        var sorted = string.Join(",", filter.OrderBy(g => g));
        var hash = Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(sorted)))[..16];
        var membershipKey = $"{_cacheKeyPrefixUserFilteredGroups}{_userId1}:{hash}";

        _mockMembershipCache.GetAsync(membershipKey).Returns((UserMembershipInGroupList?)null);
        _mockInnerService.GetUserMembershipInGroups(_userId1, Arg.Is<IEnumerable<string>>(ids => ids.SequenceEqual(filter)))
            .Returns(new List<Group> { new() { Id = _groupId1 }, new() { Id = _groupId2 } });

        // Act
        await _service.GetUserMembershipInGroups(_userId1, filter);

        // Assert
        await _mockMembershipCache.Received(1).SetAsync(
            membershipKey,
            Arg.Any<UserMembershipInGroupList>(),
            customExpiration);
    }

    [Test]
    public async Task GetUserMembershipInGroups_WithUnorderedFilter_GeneratesDeterministicCacheKey()
    {
        // Arrange
        var filterA = new List<string> { _groupId2, _groupId1, _groupId3 };
        var filterB = new List<string> { _groupId3, _groupId2, _groupId1 };

        static string BuildKey(IEnumerable<string> filter)
        {
            var sorted = string.Join(",", filter.OrderBy(g => g));
            var hash = Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(sorted)))[..16];
            return $"{_cacheKeyPrefixUserFilteredGroups}{_userId1}:{hash}";
        }

        var keyA = BuildKey(filterA);
        var keyB = BuildKey(filterB);

        _mockMembershipCache.GetAsync(keyA).Returns((UserMembershipInGroupList?)null);
        _mockInnerService.GetUserMembershipInGroups(_userId1, Arg.Is<IEnumerable<string>>(ids => ids.SequenceEqual(filterA)))
            .Returns(new List<Group> { new() { Id = _groupId1 } });

        _mockMembershipCache.GetAsync(keyB).Returns((UserMembershipInGroupList?)null);
        _mockInnerService.GetUserMembershipInGroups(_userId1, Arg.Is<IEnumerable<string>>(ids => ids.SequenceEqual(filterB)))
            .Returns(new List<Group> { new() { Id = _groupId1 } });

        // Act
        await _service.GetUserMembershipInGroups(_userId1, filterA);
        await _service.GetUserMembershipInGroups(_userId1, filterB);

        // Assert
        Assert.That(keyA, Is.EqualTo(keyB));
    }

    [Test]
    public async Task GetUserMembershipInGroups_WithDifferentFilterOrder_ReusesCachedResult()
    {
        // Arrange
        var filterA = new List<string> { _groupId2, _groupId1 };
        var filterB = new List<string> { _groupId1, _groupId2 };

        var group1 = new Group { Id = _groupId1, DisplayName = "Group1" };
        var group2 = new Group { Id = _groupId2, DisplayName = "Group2" };

        var sorted = string.Join(",", filterA.OrderBy(g => g));
        var hash = Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(sorted)))[..16];
        var membershipKey = $"{_cacheKeyPrefixUserFilteredGroups}{_userId1}:{hash}";

        // First call - cache miss, then cache hit on second call
        _mockMembershipCache.GetAsync(membershipKey)
            .Returns(null, new UserMembershipInGroupList { _groupId1, _groupId2 });

        _mockGroupCache.GetManyAsync(Arg.Any<IEnumerable<string>>())
            .Returns(new Dictionary<string, Group?>
            {
                { _groupId1, group1 },
                { _groupId2, group2 }
            });

        _mockInnerService.GetUserMembershipInGroups(_userId1, Arg.Any<IEnumerable<string>>())
            .Returns(new List<Group> { group1, group2 });

        // Act
        await _service.GetUserMembershipInGroups(_userId1, filterA);
        var result = await _service.GetUserMembershipInGroups(_userId1, filterB);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result, Has.Count.EqualTo(2));
            Assert.That(result.Select(g => g.Id), Is.EquivalentTo(new[] { _groupId1, _groupId2 }));
        }

        // Should only call inner service once (first call), second uses cache
        await _mockInnerService.Received(1).GetUserMembershipInGroups(
             _userId1,
            Arg.Any<IEnumerable<string>>());
    }

    #endregion

    #region GetUserOnPremisePropertiesAsync Tests

    [Test]
    public async Task GetUserOnPremisePropertiesAsync_WithCachedProperties_ReturnsFromCache()
    {
        // Arrange
        var userId = _userId1;
        var cacheKey = $"{_cacheKeyPrefixUserOnPremProps}{userId}";
        var cachedProps = new UserPropertiesDictionary(new Dictionary<string, string> { { "prop1", "value1" } });

        _mockPropertiesCache.GetOrAddAsync(
            cacheKey,
            Arg.Any<TimeSpan>(),
            Arg.Any<Func<Task<UserPropertiesDictionary>>>())
            .Returns(cachedProps);

        // Act
        var result = await _service.GetUserOnPremisePropertiesAsync(userId);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result, Has.Count.EqualTo(1));
            Assert.That(result["prop1"], Is.EqualTo("value1"));
        }

        await _mockInnerService.DidNotReceive().GetUserOnPremisePropertiesAsync(userId);
    }

    [Test]
    public async Task GetUserOnPremisePropertiesAsync_WithNonCachedProperties_CachesAndReturns()
    {
        // Arrange
        var userId = _userId2;
        var cacheKey = $"{_cacheKeyPrefixUserOnPremProps}{userId}";

        var fetchedProps = new Dictionary<string, string> { { "p", "v" } };
        _mockInnerService.GetUserOnPremisePropertiesAsync(userId).Returns(fetchedProps);

        _mockPropertiesCache.GetOrAddAsync(
                cacheKey,
                Arg.Any<TimeSpan>(),
                Arg.Any<Func<Task<UserPropertiesDictionary>>>())
            .Returns(callInfo =>
            {
                var factory = callInfo.ArgAt<Func<Task<UserPropertiesDictionary>>>(2);
                return factory();
            });

        // Act
        var result = await _service.GetUserOnPremisePropertiesAsync(userId);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result, Has.Count.EqualTo(1));
            Assert.That(result["p"], Is.EqualTo("v"));
        }

        await _mockInnerService.Received(1).GetUserOnPremisePropertiesAsync(userId);
        await _mockPropertiesCache.Received(1).GetOrAddAsync(
            cacheKey,
            _mockCacheConfig.UserExpiration,
            Arg.Any<Func<Task<UserPropertiesDictionary>>>());
    }

    [Test]
    public async Task GetUserOnPremisePropertiesAsync_WithEmptyProperties_ReturnsEmpty()
    {
        // Arrange
        var userId = _userId3;
        var cacheKey = $"{_cacheKeyPrefixUserOnPremProps}{userId}";

        _mockInnerService.GetUserOnPremisePropertiesAsync(userId).Returns(new Dictionary<string, string>());

        _mockPropertiesCache.GetOrAddAsync(
                cacheKey,
                Arg.Any<TimeSpan>(),
                Arg.Any<Func<Task<UserPropertiesDictionary>>>())
            .Returns(callInfo =>
            {
                var factory = callInfo.ArgAt<Func<Task<UserPropertiesDictionary>>>(2);
                return factory();
            });

        // Act
        var result = await _service.GetUserOnPremisePropertiesAsync(userId);

        // Assert
        Assert.That(result, Is.Empty);

        await _mockInnerService.Received(1).GetUserOnPremisePropertiesAsync(userId);
    }

    [Test]
    public async Task GetUserOnPremisePropertiesAsync_UsesCorrectCacheExpiration()
    {
        // Arrange
        var customExpiration = TimeSpan.FromHours(3);
        _mockCacheConfig.UserExpiration.Returns(customExpiration);

        var userId = _userId1;
        var cacheKey = $"{_cacheKeyPrefixUserOnPremProps}{userId}";

        var fetchedProps = new Dictionary<string, string> { { "key1", "value1" } };
        _mockInnerService.GetUserOnPremisePropertiesAsync(userId).Returns(fetchedProps);

        _mockPropertiesCache.GetOrAddAsync(
                cacheKey,
                Arg.Any<TimeSpan>(),
                Arg.Any<Func<Task<UserPropertiesDictionary>>>())
         .Returns(callInfo =>
         {
             var factory = callInfo.ArgAt<Func<Task<UserPropertiesDictionary>>>(2);
             return factory();
         });

        // Act
        await _service.GetUserOnPremisePropertiesAsync(userId);

        // Assert
        await _mockPropertiesCache.Received(1).GetOrAddAsync(
            cacheKey,
            customExpiration,
            Arg.Any<Func<Task<UserPropertiesDictionary>>>());
    }

    #endregion

    #region GetUserPropertiesAsync Tests

    [Test]
    public async Task GetUserPropertiesAsync_WithCachedProperties_ReturnsFromCache()
    {
        // Arrange
        var userId = _userId1;
        var cacheKey = $"{_cacheKeyPrefixUserProps}{userId}";
        var cachedProps = new UserPropertiesDictionary(new Dictionary<string, string> { { "propX", "valueX" } });

        _mockPropertiesCache.GetOrAddAsync(
                cacheKey,
                Arg.Any<TimeSpan>(),
                Arg.Any<Func<Task<UserPropertiesDictionary>>>())
            .Returns(cachedProps);

        // Act
        var result = await _service.GetUserPropertiesAsync(userId);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result, Has.Count.EqualTo(1));
            Assert.That(result["propX"], Is.EqualTo("valueX"));
        }

        await _mockInnerService.DidNotReceive().GetUserPropertiesAsync(userId);
    }

    [Test]
    public async Task GetUserPropertiesAsync_WithNonCachedProperties_CachesAndReturns()
    {
        // Arrange
        var userId = _userId2;
        var cacheKey = $"{_cacheKeyPrefixUserProps}{userId}";

        var fetchedProps = new Dictionary<string, string> { { "k", "val" } };
        _mockInnerService.GetUserPropertiesAsync(userId).Returns(fetchedProps);

        _mockPropertiesCache.GetOrAddAsync(
                cacheKey,
                Arg.Any<TimeSpan>(),
                Arg.Any<Func<Task<UserPropertiesDictionary>>>())
            .Returns(callInfo =>
            {
                var factory = callInfo.ArgAt<Func<Task<UserPropertiesDictionary>>>(2);
                return factory();
            });

        // Act
        var result = await _service.GetUserPropertiesAsync(userId);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result, Has.Count.EqualTo(1));
            Assert.That(result["k"], Is.EqualTo("val"));
        }

        await _mockInnerService.Received(1).GetUserPropertiesAsync(userId);
        await _mockPropertiesCache.Received(1).GetOrAddAsync(
            cacheKey,
            _mockCacheConfig.UserExpiration,
            Arg.Any<Func<Task<UserPropertiesDictionary>>>());
    }

    [Test]
    public async Task GetUserPropertiesAsync_WithEmptyProperties_ReturnsEmpty()
    {
        // Arrange
        var userId = _userId3;
        var cacheKey = $"{_cacheKeyPrefixUserProps}{userId}";

        _mockInnerService.GetUserPropertiesAsync(userId).Returns(new Dictionary<string, string>());

        _mockPropertiesCache.GetOrAddAsync(
                cacheKey,
                Arg.Any<TimeSpan>(),
                Arg.Any<Func<Task<UserPropertiesDictionary>>>())
            .Returns(callInfo =>
            {
                var factory = callInfo.ArgAt<Func<Task<UserPropertiesDictionary>>>(2);
                return factory();
            });

        // Act
        var result = await _service.GetUserPropertiesAsync(userId);

        // Assert
        Assert.That(result, Is.Empty);

        await _mockInnerService.Received(1).GetUserPropertiesAsync(userId);
    }

    [Test]
    public async Task GetUserPropertiesAsync_UsesCorrectCacheExpiration()
    {
        // Arrange
        var customExpiration = TimeSpan.FromHours(4);
        _mockCacheConfig.UserExpiration.Returns(customExpiration);

        var userId = _userId1;
        var cacheKey = $"{_cacheKeyPrefixUserProps}{userId}";

        var fetchedProps = new Dictionary<string, string> { { "keyA", "valueA" } };
        _mockInnerService.GetUserPropertiesAsync(userId).Returns(fetchedProps);

        _mockPropertiesCache.GetOrAddAsync(
                cacheKey,
                Arg.Any<TimeSpan>(),
                Arg.Any<Func<Task<UserPropertiesDictionary>>>())
            .Returns(callInfo =>
            {
                var factory = callInfo.ArgAt<Func<Task<UserPropertiesDictionary>>>(2);
                return factory();
            });

        // Act
        await _service.GetUserPropertiesAsync(userId);

        // Assert
        await _mockPropertiesCache.Received(1).GetOrAddAsync(
            cacheKey,
            customExpiration,
            Arg.Any<Func<Task<UserPropertiesDictionary>>>());
    }

    #endregion
}
