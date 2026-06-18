using System.Net.Http.Json;
using System.Web;
using Microsoft.Extensions.Logging;
using IdentityServer.MicrosoftGraph.Extensions;

namespace IdentityServer.MicrosoftGraph;

internal abstract class MicrosoftGraphApiClientBase
{
    protected static readonly IReadOnlyDictionary<string, string> EmptyHeaders = new Dictionary<string, string>();
    protected static readonly IReadOnlyDictionary<string, string> PreferModernSearchHeaders = new Dictionary<string, string>()
    {
        { "Prefer", "legacySearch=false" }, // https://developer.microsoft.com/en-us/graph/known-issues/?search=18185
    };

    protected readonly IHttpClientFactory _clientFactory;
    protected readonly ILogger _logger;

    protected abstract string ClientName { get; }

    protected MicrosoftGraphApiClientBase(IHttpClientFactory clientFactory, ILogger logger)
    {
        _clientFactory = clientFactory;
        _logger = logger;
    }

    protected HttpClient CreateClient() => _clientFactory.CreateClient(ClientName);

    protected static string BuildResourceRelativePath(string resource, string? select, string? filter)
    {
        return AppendQuery($"/v1.0/{resource}", select, filter);
    }

    protected static string BuildItemRelativePath(string resource, string id, string? select, string? filter)
    {
        return AppendQuery($"/v1.0/{resource}/{id}", select, filter);
    }

    private static string AppendQuery(string relativePath, string? select, string? filter)
    {
        var query = HttpUtility.ParseQueryString(string.Empty);

        if (!string.IsNullOrEmpty(select))
        {
            query["$select"] = select;
        }
        if (!string.IsNullOrEmpty(filter))
        {
            query["$filter"] = filter;
        }

        var queryString = query.ToString();
        if (string.IsNullOrEmpty(queryString))
        {
            return relativePath;
        }

        return $"{relativePath}?{queryString}";
    }

    protected Task<TResponse?> GetByIdAsync<TResponse>(string relativePath)
    {
        var client = CreateClient();
        return GetByIdAsync<TResponse>(client, relativePath);
    }

    protected Task<TResponse?> GetByIdAsync<TResponse>(Uri requestUrl)
    {
        var client = CreateClient();
        return GetByIdAsync<TResponse>(client, requestUrl, EmptyHeaders);
    }

    protected Task<TResponse?> GetByIdAsync<TResponse>(HttpClient client, string relativePath)
    {
        var requestUrl = new Uri(client.BaseAddress ?? Constants.MicrosoftGraphUri, relativePath);
        return GetByIdAsync<TResponse>(client, requestUrl, EmptyHeaders);
    }

    protected async Task<TResponse?> GetByIdAsync<TResponse>(HttpClient client, Uri requestUrl, IEnumerable<KeyValuePair<string, string>> extraHeaders)
    {
        using var request = new HttpRequestMessage(HttpMethod.Get, requestUrl);

        foreach (var header in extraHeaders)
        {
            request.Headers.Add(header.Key, header.Value);
        }

        return await SendAsync<TResponse>(client, request);
    }

    protected async Task<TResponse?> SendAsync<TResponse>(HttpClient client, HttpRequestMessage request)
    {
        using var response = await client.SendAsync(request);

        if (response.IsSuccessStatusCode)
        {
            return await response.Content.ReadFromJsonAsync<TResponse>();
        }
        else if (response.StatusCode == System.Net.HttpStatusCode.NotFound)
        {
            return default;
        }
        else
        {
            await response.LogErrorResponseAsync(nameof(SendAsync), request.RequestUri, _logger);
            throw new HttpRequestException($"MsGraph request failed: {response.StatusCode}");
        }
    }
}
