using IdentityServer.Abstraction.Entities.EntraEntities;

namespace IdentityServer.MicrosoftGraph;

public interface IMicrosoftGraphUserApi
{
    /// <summary>
    /// Endpoint to retrieve on premise properties of a user.
    /// </summary>
    /// <remarks>At the moment only fetches onPremisesSamAccountName property.</remarks>
    /// <param name="userObjectId">User Object ID (from 'oid' claim)</param>
    /// <returns>User on premises properties</returns>
    Task<UserOnPremisePropertiesResponse?> GetUserOnPremisePropertiesAsync(string userObjectId);

    /// <summary>
    /// Endpoint to retrieve additional properties of a user.
    /// </summary>
    /// <param name="userObjectId">User Object ID (from 'oid' claim)</param>
    /// <returns>User properties</returns>
    Task<UserAdditionalPropertiesResponse?> GetUserPropertiesAsync(string userObjectId);

    /// <summary>
    /// Endpoint to search users by displayName. Continuation tokens are not supported to prevent directory dump.
    /// </summary>
    /// <param name="displayName">Search string</param>
    /// <returns>A page with found users</returns>
    Task<UserResponse> SearchUsersByDisplayNameAsync(string displayName);

    /// <summary>
    /// Returns a user from EntraID without any filtering or an empty list.
    /// </summary>
    /// <param name="userObjectId">User Object ID (from 'oid' claim)</param>
    /// <returns>Zero or one user</returns>
    Task<UserResponse> GetUserByObjectIdAsync(string userObjectId);

    /// <summary>
    /// Returns users from EntraID without any filtering.
    /// </summary>
    /// <param name="userObjectIds"></param>
    /// <returns>The list of all found users</returns>
    Task<UserResponse> GetUsersByObjectIdsAsync(IEnumerable<string> userObjectIds);

    /// <summary>
    /// Endpoint to check user's membership in specific groups.
    /// </summary>
    /// <param name="userId">User Object ID</param>
    /// <param name="groupIdFilter">Groups to check for membership. Up to 20 Entra Group IDs can be provided.</param>
    /// <returns>Returns from the provided list the IDs of groups where a specified user is a member.</returns>
    Task<GroupResponse> GetUserMembershipInGroups(string userId, IEnumerable<string> groupIdFilter);
}
