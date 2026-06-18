namespace IdentityServer.Abstraction.Entities;

/// <summary>
/// Used in IdentityServer API to represent Client search results.
/// </summary>
/// <typeparam name="T">Type of the result.</typeparam>
public class SearchResult<T>
{
    public int TotalCount { get; set; }
    public int PageNumber { get; set; }
    public int PageSize { get; set; }
    public List<T> Page { get; set; } = new List<T>();
}

/// <summary>
/// Used in Admin API and UI to represent User/Group/Client search results.
/// </summary>
/// <typeparam name="T">Type of the result.</typeparam>
public class SearchResult2<T>
{
    public string? ErrorMessage { get; set; }
    public string? SkipToken { get; set; }
    public List<T>? Page { get; set; }

    public void Deconstruct(out List<T>? result, out string? skipToken, out string? errorMessage)
    {
        result = Page;
        skipToken = SkipToken;
        errorMessage = ErrorMessage;
    }
}
