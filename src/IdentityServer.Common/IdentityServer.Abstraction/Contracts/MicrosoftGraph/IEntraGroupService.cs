using IdentityServer.Abstraction.Entities.EntraEntities;

namespace IdentityServer.Abstraction.Contracts.MicrosoftGraph;

public interface IEntraGroupService
{
    Task<GroupResponse> GetGroupByObjectIdAsync(string groupId);

    Task<GroupResponse> GetGroupsByObjectIdsAsync(IEnumerable<string> groupIds);

    Task<GroupResponse> GetGroupsByDisplayNameAsync(string searchString, string? skipToken);

    Task<UserResponse> GetGroupMembersAsync(string groupId, string? skipToken);

    Task<List<User>> GetGroupMembersAsync(string groupId);
}
