using IdentityServer.Abstraction.Entities.EntraEntities;

namespace IdentityServer.Abstraction.Contracts.MicrosoftGraph;

public interface IEntraUserService
{
    Task<List<Group>> GetUserMembershipInGroups(string userId, IEnumerable<string> groupIdFilter);

    Task<UserResponse> GetUsersByDisplayNameAsync(string searchString);

    Task<UserResponse> GetUserByObjectIdAsync(string userId);

    Task<UserResponse> GetUsersByObjectIdsAsync(IEnumerable<string> userIds);

    Task<Dictionary<string, string>> GetUserOnPremisePropertiesAsync(string userId);

    Task<Dictionary<string, string>> GetUserPropertiesAsync(string userId);
}
