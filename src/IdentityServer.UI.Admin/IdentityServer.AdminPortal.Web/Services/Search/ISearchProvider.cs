using IdentityServer.Abstraction.Entities;

namespace IdentityServer.AdminPortal.Web.Services.Search;

public interface ISearchProvider<T>
{
    Task<SearchResult2<T>> SearchAsync(string input, string? skipToken);
}
