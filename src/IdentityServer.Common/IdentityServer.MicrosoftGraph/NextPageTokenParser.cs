using System.Web;

namespace IdentityServer.MicrosoftGraph;

internal static class NextPageTokenParser
{
    public static string? ExtractSkipToken(string? nextPageLink)
    {
        if (string.IsNullOrEmpty(nextPageLink))
        {
            return null;
        }

        var uri = new Uri(nextPageLink);
        var queryParameters = HttpUtility.ParseQueryString(uri.Query);

        return queryParameters["$skiptoken"] ?? queryParameters["$skipToken"];
    }
}
