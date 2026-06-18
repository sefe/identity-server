using System.Net.Http.Json;
using System.Web;
using Microsoft.Extensions.Logging;
using IdentityServer.Abstraction.Entities.EntraEntities;
using IdentityServer.MicrosoftGraph.Extensions;

namespace IdentityServer.MicrosoftGraph;

internal class MicrosoftGraphGroupApiClient : MicrosoftGraphApiClientBase, IMicrosoftGraphGroupApi
{
    protected override string ClientName => Constants.HttpClientNames.GraphGroupsClientName;

    public MicrosoftGraphGroupApiClient(IHttpClientFactory clientFactory, ILogger<MicrosoftGraphGroupApiClient> logger)
        : base(clientFactory, logger)
    {
    }

    public async Task<GroupResponse> GetGroupByObjectIdAsync(Guid groupId)
    {
        var result = new GroupResponse();
        var group = await GetByIdAsync<Group>(BuildItemRelativePath("groups", groupId.ToString(), "displayName,id", string.Empty));
        if (group != null)
        {
            result.Groups.Add(group);
        }
        return result;
    }

    public async Task<GroupResponse> GetGroupsByObjectIdsAsync(IEnumerable<Guid> groupIds)
    {
        var result = new GroupResponse();

        var uniqueGroupIds = groupIds.Select(g => g.ToString()).Distinct(StringComparer.OrdinalIgnoreCase).ToArray();
        if (uniqueGroupIds.Length == 0)
        {
            return result;
        }

        const int batchSize = 15; // https://developer.microsoft.com/en-us/graph/known-issues/?search=13635
        var client = CreateClient();

        var batches = uniqueGroupIds.Chunk(batchSize).ToArray();

        var tasks = new List<Task<GroupResponse?>>();

        foreach (var batch in batches)
        {
            var relativePath = $"/v1.0/groups?$select=id,displayName&$filter=id in ('{string.Join("','", batch)}')";
            tasks.Add(GetByIdAsync<GroupResponse?>(client, relativePath));
        }

        var jobs = await Task.WhenAll(tasks);
        result.Groups.AddRange(jobs.SelectMany(response => response == null ? Enumerable.Empty<Group>() : response.Groups));

        return result;
    }

    public async Task<UserResponse> GetUsersByGroupIdAsync(Guid groupId, string? continuationToken = null)
    {
        var client = CreateClient();
        var requestUrlBuilder = new UriBuilder(new Uri(client.BaseAddress ?? Constants.MicrosoftGraphUri, $"/v1.0/groups/{groupId}/members"));

        var query = HttpUtility.ParseQueryString(string.Empty);
        query["$select"] = "displayName,id,accountEnabled";
        query["$top"] = "999";

        if (!string.IsNullOrEmpty(continuationToken))
        {
            query["$skiptoken"] = continuationToken;
        }
        requestUrlBuilder.Query = query.ToString();

        using var request = new HttpRequestMessage(HttpMethod.Get, requestUrlBuilder.Uri);
        using var response = await client.SendAsync(request);

        if (response.IsSuccessStatusCode)
        {
            return await response.Content.ReadFromJsonAsync<UserResponse>() ?? new UserResponse();
        }

        await response.LogErrorResponseAsync(nameof(GetUsersByGroupIdAsync), request.RequestUri, _logger);

        throw new HttpRequestException($"Failed to retrieve users of a group: {response.StatusCode}");
    }

    /// <inheritdoc/>
    public async Task<GroupResponse> SearchGroupsByDisplayNameAsync(string displayName, string? continuationToken = null)
    {
        var client = CreateClient();
        var requestUrlBuilder = new UriBuilder(new Uri(client.BaseAddress ?? Constants.MicrosoftGraphUri, "/v1.0/groups"));

        displayName = displayName.Replace("\\", "\\\\").Replace("\"", "\\\"");

        var query = HttpUtility.ParseQueryString(string.Empty);
        query["$search"] = $"\"displayName:{displayName}\"";
        if (!string.IsNullOrEmpty(continuationToken))
        {
            query["$skiptoken"] = continuationToken;
        }
        requestUrlBuilder.Query = query.ToString();

        return await GetByIdAsync<GroupResponse?>(client, requestUrlBuilder.Uri, PreferModernSearchHeaders) ?? new GroupResponse();
    }
}
