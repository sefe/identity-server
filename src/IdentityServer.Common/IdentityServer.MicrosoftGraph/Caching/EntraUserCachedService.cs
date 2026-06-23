// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

using System.Security.Cryptography;
using System.Text;
using IdentityServer.Abstraction.Configs;
using IdentityServer.Abstraction.Contracts;
using IdentityServer.Abstraction.Contracts.MicrosoftGraph;
using IdentityServer.Abstraction.Entities.EntraEntities;

namespace IdentityServer.MicrosoftGraph.Caching;

/// <summary>
/// Caching decorator for <see cref="IEntraUserService"/>.
/// </summary>
internal class EntraUserCachedService : IEntraUserService
{
    private readonly IEntraUserService _inner;
    private readonly ICache<User> _userCache;
    private readonly ICache<Group> _groupCache;
    private readonly ICache<UserMembershipInGroupList> _membershipCache;
    private readonly ICache<UserPropertiesDictionary> _propertiesCache;
    private readonly IMicrosoftEntraCacheConfig _cacheConfig;

    public EntraUserCachedService(
        IEntraUserService inner,
        ICache<User> userCache,
        ICache<Group> groupCache,
        ICache<UserMembershipInGroupList> membershipCache,
        ICache<UserPropertiesDictionary> propertiesCache,
        IMicrosoftEntraCacheConfig cacheConfig)
    {
        _inner = inner;
        _userCache = userCache;
        _groupCache = groupCache;
        _membershipCache = membershipCache;
        _propertiesCache = propertiesCache;
        _cacheConfig = cacheConfig;
    }

    public Task<UserResponse> GetUsersByDisplayNameAsync(string searchString)
    {
        // Don't cache search results as they can be dynamic
        return _inner.GetUsersByDisplayNameAsync(searchString);
    }

    public async Task<UserResponse> GetUserByObjectIdAsync(string userId)
    {
        var user = await _userCache.GetOrAddAsync(
            userId,
            _cacheConfig.UserExpiration,
            async () =>
            {
                var response = await _inner.GetUserByObjectIdAsync(userId);
                return response?.Users?.FirstOrDefault()!;
            });

        var result = new UserResponse();
        if (user != null)
        {
            result.Users.Add(user);
        }

        return result;
    }

    public async Task<UserResponse> GetUsersByObjectIdsAsync(IEnumerable<string> userIds)
    {
        var userIdList = userIds.ToList();
        var result = new UserResponse();

        if (userIdList.Count == 0)
        {
            return result;
        }

        var cachedUsers = await _userCache.GetManyAsync(userIdList);

        // Identify cache misses
        var missedUserIds = new List<string>();
        foreach (var userId in userIdList)
        {
            if (cachedUsers.TryGetValue(userId, out var user) && user != null)
            {
                result.Users.Add(user);
            }
            else
            {
                missedUserIds.Add(userId);
            }
        }

        // Fetch missing users from the underlying service
        if (missedUserIds.Count > 0)
        {
            var fetchedResponse = await _inner.GetUsersByObjectIdsAsync(missedUserIds);
            if (fetchedResponse.Users.Count > 0)
            {
                var itemsToCache = new Dictionary<string, User>();

                foreach (var user in fetchedResponse.Users)
                {
                    result.Users.Add(user);
                    itemsToCache[user.OId] = user;
                }

                await _userCache.SetManyAsync(itemsToCache, _cacheConfig.UserExpiration);
            }
        }

        return result;
    }

    public async Task<List<Group>> GetUserMembershipInGroups(string userId, IEnumerable<string> groupIdFilter)
    {
        var groupIdList = groupIdFilter.ToList();

        if (groupIdList.Count == 0)
        {
            return new List<Group>();
        }

        // Create a deterministic, bounded-length cache key using hash of sorted group IDs
        var sortedGroupIds = string.Join(",", groupIdList.OrderBy(g => g));
        var filterHash = Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(sortedGroupIds)))[..16];
        var membershipCacheKey = $"user-filtered-groups:{userId}:{filterHash}";

        var cachedGroupIds = await _membershipCache.GetAsync(membershipCacheKey);
        if (cachedGroupIds != null && cachedGroupIds.Count > 0)
        {
            var cachedGroups = await _groupCache.GetManyAsync(cachedGroupIds);
            var allGroupsFound = cachedGroupIds.All(id => cachedGroups.TryGetValue(id, out var group) && group != null);
            if (allGroupsFound)
            {
                return cachedGroupIds
                            .Select(id => cachedGroups[id]!)
                            .ToList();
            }
        }

        var groups = await _inner.GetUserMembershipInGroups(userId, groupIdList);

        if (groups.Count > 0)
        {
            var groupIds = new UserMembershipInGroupList();

            foreach (var group in groups)
            {
                groupIds.Add(group.Id);
            }

            // do not cache returned groups because they don't have any fields except ID

            // Cache the membership list (group IDs for this user with filter)
            await _membershipCache.SetAsync(membershipCacheKey, groupIds, _cacheConfig.UserExpiration);
        }

        return groups;
    }

    public async Task<Dictionary<string, string>> GetUserOnPremisePropertiesAsync(string userId)
    {
        var cacheKey = $"user-onprem-props:{userId}";

        var result = await _propertiesCache.GetOrAddAsync(cacheKey, _cacheConfig.UserExpiration, async () =>
        {
            var props = await _inner.GetUserOnPremisePropertiesAsync(userId);
            return new UserPropertiesDictionary(props);
        });

        return result;
    }

    public async Task<Dictionary<string, string>> GetUserPropertiesAsync(string userId)
    {
        var cacheKey = $"user-props:{userId}";

        var result = await _propertiesCache.GetOrAddAsync(cacheKey, _cacheConfig.UserExpiration, async () =>
        {
            var props = await _inner.GetUserPropertiesAsync(userId);
            return new UserPropertiesDictionary(props);
        });

        return result;
    }
}
