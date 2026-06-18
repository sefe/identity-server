using IdentityServer.Abstraction.Configs;
using IdentityServer.Abstraction.Contracts;
using IdentityServer.Abstraction.Contracts.MicrosoftGraph;
using IdentityServer.Abstraction.Entities.EntraEntities;

namespace IdentityServer.MicrosoftGraph.Caching;

/// <summary>
/// Caching decorator for <see cref="IEntraGroupService"/>.
/// </summary>
internal class EntraGroupCachedService : IEntraGroupService
{
    private const string _membershipCacheKeyPrefix = "group-members:";

    private readonly IEntraGroupService _inner;
    private readonly ICache<Group> _groupCache;
    private readonly ICache<User> _userCache;
    private readonly ICache<GroupMembersList> _membershipCache;
    private readonly IMicrosoftEntraCacheConfig _cacheConfig;

    public EntraGroupCachedService(
        IEntraGroupService inner,
        ICache<Group> groupCache,
        ICache<User> userCache,
        ICache<GroupMembersList> membershipCache,
        IMicrosoftEntraCacheConfig cacheConfig)
    {
        _inner = inner;
        _groupCache = groupCache;
        _userCache = userCache;
        _membershipCache = membershipCache;
        _cacheConfig = cacheConfig;
    }

    public async Task<GroupResponse> GetGroupByObjectIdAsync(string groupId)
    {
        var group = await _groupCache.GetOrAddAsync(
            groupId,
            _cacheConfig.GroupExpiration,
            async () =>
            {
                var response = await _inner.GetGroupByObjectIdAsync(groupId);
                return response?.Groups?.FirstOrDefault()!;
            });

        var result = new GroupResponse();
        if (group != null)
        {
            result.Groups.Add(group);
        }

        return result;
    }

    public async Task<GroupResponse> GetGroupsByObjectIdsAsync(IEnumerable<string> groupIds)
    {
        var groupIdList = groupIds.ToList();
        var result = new GroupResponse();

        if (groupIdList.Count == 0)
        {
            return result;
        }

        // Try to get all from cache in a single roundtrip
        var cachedGroups = await _groupCache.GetManyAsync(groupIdList);

        // Identify cache misses
        var missedGroupIds = new List<string>();
        foreach (var groupId in groupIdList)
        {
            if (cachedGroups.TryGetValue(groupId, out var group) && group != null)
            {
                result.Groups.Add(group);
            }
            else
            {
                missedGroupIds.Add(groupId);
            }
        }

        // Fetch missing groups from the underlying service
        if (missedGroupIds.Count > 0)
        {
            var fetchedResponse = await _inner.GetGroupsByObjectIdsAsync(missedGroupIds);

            // Add fetched groups to result and cache them
            if (fetchedResponse.Groups.Count > 0)
            {
                var itemsToCache = new Dictionary<string, Group>();

                foreach (var group in fetchedResponse.Groups)
                {
                    result.Groups.Add(group);
                    itemsToCache[group.Id] = group;
                }

                // Cache all fetched groups in a single roundtrip
                await _groupCache.SetManyAsync(itemsToCache, _cacheConfig.GroupExpiration);
            }
        }

        return result;
    }

    public Task<UserResponse> GetGroupMembersAsync(string groupId, string? skipToken)
    {
        // Don't cache paginated results with skip tokens
        return _inner.GetGroupMembersAsync(groupId, skipToken);
    }

    public async Task<List<User>> GetGroupMembersAsync(string groupId)
    {
        var membershipCacheKey = $"{_membershipCacheKeyPrefix}{groupId}";

        var cachedUserIds = await _membershipCache.GetAsync(membershipCacheKey);
        if (cachedUserIds != null && cachedUserIds.Count > 0)
        {
            var cachedUsers = await _userCache.GetManyAsync(cachedUserIds);
            var allFoundUsers = cachedUsers.Where(kv => kv.Value != null).Select(kv => kv.Value!).ToList();
            if (allFoundUsers.Count == cachedUserIds.Count)
            {
                return allFoundUsers;
            }
        }

        // Cache miss or incomplete - fetch from underlying service
        var users = await _inner.GetGroupMembersAsync(groupId);

        if (users.Count > 0)
        {
            var usersToCache = users.ToDictionary(u => u.OId, u => u);

            // Cache users in batch
            await _userCache.SetManyAsync(usersToCache, _cacheConfig.UserExpiration);

            // Cache the membership list (user IDs for this group)
            await _membershipCache.SetAsync(membershipCacheKey, new GroupMembersList(usersToCache.Keys), _cacheConfig.UserExpiration);
        }

        return users;
    }

    public Task<GroupResponse> GetGroupsByDisplayNameAsync(string searchString, string? skipToken)
    {
        // Don't cache search results as they can be dynamic
        return _inner.GetGroupsByDisplayNameAsync(searchString, skipToken);
    }
}
