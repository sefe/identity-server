// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

using IdentityServer.Abstraction.Entities.EntraEntities;

namespace IdentityServer.MicrosoftGraph;

public interface IMicrosoftGraphGroupApi
{
    /// <summary>
    /// Retrieves the details of a group based on its unique identifier.
    /// </summary>
    /// <param name="groupId">The unique identifier of the group to retrieve.</param>
    /// <returns>A task that represents the asynchronous operation. The task result contains a <see cref="GroupResponse"/> object
    /// with the details of the group, or <see langword="null"/> if the group is not found.</returns>
    Task<GroupResponse> GetGroupByObjectIdAsync(Guid groupId);

    /// <summary>
    /// Retrieves group information for the specified collection of group object IDs.
    /// </summary>
    /// <remarks>This method performs an asynchronous operation to fetch group details based on the provided
    /// object IDs.  Ensure that the collection contains valid and unique group IDs.</remarks>
    /// <param name="groupIds">A collection of <see cref="Guid"/> values representing the object IDs of the groups to retrieve.</param>
    /// <returns>A task that represents the asynchronous operation. The task result contains a <see cref="GroupResponse"/> object
    /// with the details of the requested groups.</returns>
    Task<GroupResponse> GetGroupsByObjectIdsAsync(IEnumerable<Guid> groupIds);

    /// <summary>
    /// Endpoint to search groups by displayName with support for continuation tokens
    /// </summary>
    /// <param name="displayName">Search string</param>
    /// <param name="continuationToken">Next page token, if available</param>
    /// <returns>A page with found groups</returns>
    Task<GroupResponse> SearchGroupsByDisplayNameAsync(string displayName, string? continuationToken = null);

    /// <summary>
    /// Retrieves a paginated list of users belonging to the specified group.
    /// </summary>
    /// <remarks>Use the continuation token from the returned <see cref="UserResponse"/> to fetch additional
    /// pages of users, if the result set is too large to be returned in a single response.</remarks>
    /// <param name="groupId">The unique identifier of the group whose users are to be retrieved.</param>
    /// <param name="continuationToken">An optional token used to retrieve the next set of results in a paginated response. Pass <see langword="null"/>
    /// to retrieve the first page of results.</param>
    /// <returns>A <see cref="UserResponse"/> object containing the list of users and a continuation token for fetching the next
    /// page of results, if available.</returns>
    Task<UserResponse> GetUsersByGroupIdAsync(Guid groupId, string? continuationToken = null);
}
