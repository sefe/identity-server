using IdentityServer.Abstraction.Contracts.MicrosoftGraph;
using IdentityServer.Abstraction.Entities.EntraEntities;

namespace IdentityServer.MicrosoftGraph;

internal class EntraGroupService : IEntraGroupService
{
    private readonly IMicrosoftGraphGroupApi _graphGroupApi;

    public EntraGroupService(IMicrosoftGraphGroupApi graphGroupApi)
    {
        _graphGroupApi = graphGroupApi;
    }

    public Task<GroupResponse> GetGroupByObjectIdAsync(string groupId)
    {
        if (!IsValidNonZeroGuid(groupId, out var groupGuid))
        {
            return Task.FromResult(new GroupResponse());
        }

        return _graphGroupApi.GetGroupByObjectIdAsync(groupGuid);
    }

    public Task<GroupResponse> GetGroupsByObjectIdsAsync(IEnumerable<string> groupIds)
    {
        var validGroupIds = groupIds
            .Select(id => IsValidNonZeroGuid(id, out var g) ? g : Guid.Empty)
            .Where(g => g != Guid.Empty)
            .ToList();

        if (validGroupIds.Count == 0)
        {
            return Task.FromResult(new GroupResponse());
        }

        return _graphGroupApi.GetGroupsByObjectIdsAsync(validGroupIds);
    }

    public async Task<UserResponse> GetGroupMembersAsync(string groupId, string? skipToken)
    {
        if (!IsValidNonZeroGuid(groupId, out var groupGuid))
        {
            return new UserResponse();
        }

        var users = await _graphGroupApi.GetUsersByGroupIdAsync(groupGuid, skipToken);
        users.SkipToken = NextPageTokenParser.ExtractSkipToken(users.NextLink);
        return users;
    }

    public async Task<List<User>> GetGroupMembersAsync(string groupId)
    {
        var result = new List<User>();

        if (!IsValidNonZeroGuid(groupId, out _))
        {
            return result;
        }

        string? skipToken = null;

        do
        {
            var response = await GetGroupMembersAsync(groupId, skipToken);
            result.AddRange(response?.Users ?? []);
            skipToken = response?.SkipToken;
        }
        while (!string.IsNullOrEmpty(skipToken));

        return result;
    }

    public async Task<GroupResponse> GetGroupsByDisplayNameAsync(string searchString, string? skipToken)
    {
        var groups = await _graphGroupApi.SearchGroupsByDisplayNameAsync(searchString, skipToken);
        groups.SkipToken = NextPageTokenParser.ExtractSkipToken(groups.NextLink);
        return groups;
    }

    private static bool IsValidNonZeroGuid(string value, out Guid result)
    {
        return Guid.TryParse(value, out result) && result != Guid.Empty;
    }
}
