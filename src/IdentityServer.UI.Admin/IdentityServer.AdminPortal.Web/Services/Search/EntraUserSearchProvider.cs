using IdentityServer.Abstraction.Entities;
using IdentityServer.Abstraction.Entities.EntraEntities;

namespace IdentityServer.AdminPortal.Web.Services.Search;

public class EntraUserSearchProvider : AdminApiProviderBase, ISearchProvider<User>
{
    public EntraUserSearchProvider(IAdminApiService adminApi) : base(adminApi)
    {
    }

    public async Task<SearchResult2<User>> SearchAsync(string input, string? skipToken)
    {
        UserResponse? userSearchResult;
        string? errorMessage;

        if (Guid.TryParse(input, out var _))
        {
            (userSearchResult, errorMessage) = await AdminApi.GetUserById(input);
        }
        else
        {
            (userSearchResult, errorMessage) = await AdminApi.SearchUsers(input);
        }

        return new SearchResult2<User>
        {
            Page = userSearchResult?.Users ?? [],
            ErrorMessage = errorMessage,
        };
    }
}
