using IdentityServer.Abstraction.Entities;
using IdentityServer.Abstraction.Entities.EntraEntities;

namespace IdentityServer.AdminPortal.Web.Services.Search;

public class EntraGroupSearchProvider : AdminApiProviderBase, ISearchProvider<Group>
{
    public EntraGroupSearchProvider(IAdminApiService adminApi) : base(adminApi)
    {
    }

    public async Task<SearchResult2<Group>> SearchAsync(string input, string? skipToken)
    {
        var callResult = await AdminApi.SearchGroups(input, skipToken);
        if (callResult.IsSuccess)
        {
            return new SearchResult2<Group>
            {
                Page = callResult.Result.Groups ?? [],
                SkipToken = callResult.Result.SkipToken,
            };
        }
        else
        {
            return new SearchResult2<Group>
            {
                ErrorMessage = callResult.ErrorMessage
            };
        }
    }
}
