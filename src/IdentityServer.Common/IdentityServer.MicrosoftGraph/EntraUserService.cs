using IdentityServer.Abstraction.Contracts.MicrosoftGraph;
using IdentityServer.Abstraction.Entities.EntraEntities;
using static IdentityServer.Abstraction.Constants;

namespace IdentityServer.MicrosoftGraph;

internal class EntraUserService : IEntraUserService
{
    private readonly IMicrosoftGraphUserApi _graphUserApi;

    public EntraUserService(IMicrosoftGraphUserApi graphUserApi)
    {
        _graphUserApi = graphUserApi;
    }

    public async Task<UserResponse> GetUsersByDisplayNameAsync(string searchString)
    {
        var users = await _graphUserApi.SearchUsersByDisplayNameAsync(searchString);
        users.SkipToken = null; // prevent search continuation
        return users;
    }

    public Task<UserResponse> GetUserByObjectIdAsync(string userId)
    {
        return _graphUserApi.GetUserByObjectIdAsync(userId);
    }

    public Task<UserResponse> GetUsersByObjectIdsAsync(IEnumerable<string> userIds)
    {
        return _graphUserApi.GetUsersByObjectIdsAsync(userIds);
    }

    public async Task<List<Group>> GetUserMembershipInGroups(string userId, IEnumerable<string> groupIdFilter)
    {
        var groups = await _graphUserApi.GetUserMembershipInGroups(userId, groupIdFilter);
        return groups?.Groups ?? [];
    }

    public async Task<Dictionary<string, string>> GetUserOnPremisePropertiesAsync(string userId)
    {
        return ToDictionary(await _graphUserApi.GetUserOnPremisePropertiesAsync(userId));
    }

    public async Task<Dictionary<string, string>> GetUserPropertiesAsync(string userId)
    {
        return ToDictionary(await _graphUserApi.GetUserPropertiesAsync(userId));
    }

    private static Dictionary<string, string> ToDictionary(UserOnPremisePropertiesResponse? response)
    {
        var result = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        if (response == null)
        {
            return result;
        }

        AddClaimValue(result, ClaimNames.UserOnPremisesSamAccountName, response.OnPremisesSamAccountName);

        return result;
    }

    private static Dictionary<string, string> ToDictionary(UserAdditionalPropertiesResponse? response)
    {
        var result = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        if (response == null)
        {
            return result;
        }

        AddClaimValue(result, ClaimNames.UserObjectId, response.OId);
        AddClaimValue(result, ClaimNames.UserDisplayName, response.DisplayName);
        AddClaimValue(result, "givenName", response.GivenName);
        AddClaimValue(result, "jobTitle", response.JobTitle);
        AddClaimValue(result, ClaimNames.UserEmail, response.Mail);
        AddClaimValue(result, "mobilePhone", response.MobilePhone);
        AddClaimValue(result, "officeLocation", response.OfficeLocation);
        AddClaimValue(result, "preferredLanguage", response.PreferredLanguage);
        AddClaimValue(result, "surname", response.Surname);
        AddClaimValue(result, ClaimNames.UserPrincipalName, response.UserPrincipalName);

        return result;
    }

    private static void AddClaimValue(Dictionary<string, string> result, string key, string? value)
    {
        if (!string.IsNullOrEmpty(value))
        {
            result.Add(key, value);
        }
    }
}

