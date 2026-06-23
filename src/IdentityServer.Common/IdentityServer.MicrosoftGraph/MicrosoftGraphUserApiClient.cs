// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

using System.Net.Http.Json;
using System.Web;
using Microsoft.Extensions.Logging;
using IdentityServer.Abstraction.Entities.EntraEntities;

namespace IdentityServer.MicrosoftGraph;

internal sealed class MicrosoftGraphUserApiClient : MicrosoftGraphApiClientBase, IMicrosoftGraphUserApi
{
    private const string _userAccountEnabledFilter = "accountEnabled eq true";
    private const string _userResourceName = "users";
    private const string _primaryUserProperties = "id,displayName,accountEnabled";

    protected override string ClientName => Constants.HttpClientNames.GraphUsersClientName;

    public MicrosoftGraphUserApiClient(IHttpClientFactory clientFactory, ILogger<MicrosoftGraphUserApiClient> logger)
        : base(clientFactory, logger)
    {
    }

    /// <inheritdoc/>
    public async Task<UserResponse> GetUserByObjectIdAsync(string userObjectId)
    {
        ArgumentException.ThrowIfNullOrEmpty(userObjectId);

        var result = new UserResponse();
        var user = await GetByIdAsync<User>(BuildItemRelativePath(_userResourceName, userObjectId, _primaryUserProperties, string.Empty));
        if (user != null)
        {
            result.Users.Add(user);
        }
        return result;
    }

    public async Task<UserResponse> GetUsersByObjectIdsAsync(IEnumerable<string> userObjectIds)
    {
        ArgumentNullException.ThrowIfNull(userObjectIds);

        var result = new UserResponse();
        var userIds = userObjectIds.Distinct(StringComparer.OrdinalIgnoreCase).ToArray();
        if (userIds.Length == 0)
        {
            return result;
        }

        const int batchSize = 15; // https://developer.microsoft.com/en-us/graph/known-issues/?search=13635

        var batches = userIds.Chunk(batchSize).ToArray();

        var tasks = new List<Task<UserResponse?>>();

        foreach (var batch in batches)
        {
            var filterExpr = $"id in ('{string.Join("','", batch)}')";
            var relativeUrl = BuildResourceRelativePath(_userResourceName, _primaryUserProperties, filterExpr);
            tasks.Add(GetByIdAsync<UserResponse?>(relativeUrl));
        }

        var jobs = await Task.WhenAll(tasks);

        result.Users = jobs.SelectMany(response => response == null ? Enumerable.Empty<User>() : response.Users).ToList();

        return result;
    }

    /// <inheritdoc/>
    public Task<UserOnPremisePropertiesResponse?> GetUserOnPremisePropertiesAsync(string userObjectId)
    {
        ArgumentException.ThrowIfNullOrEmpty(userObjectId);
        var relativeUrl = BuildItemRelativePath(_userResourceName, userObjectId, "onPremisesSamAccountName", string.Empty);
        return GetByIdAsync<UserOnPremisePropertiesResponse>(relativeUrl);
    }

    /// <inheritdoc/>
    public Task<UserAdditionalPropertiesResponse?> GetUserPropertiesAsync(string userObjectId)
    {
        ArgumentException.ThrowIfNullOrEmpty(userObjectId);
        var relativeUrl = BuildItemRelativePath(_userResourceName, userObjectId, string.Empty, string.Empty);
        return GetByIdAsync<UserAdditionalPropertiesResponse>(relativeUrl);
    }

    /// <inheritdoc/>
    public async Task<UserResponse> SearchUsersByDisplayNameAsync(string displayName)
    {
        ArgumentException.ThrowIfNullOrEmpty(displayName);

        var client = CreateClient();
        var requestUrlBuilder = new UriBuilder(new Uri(client.BaseAddress ?? Constants.MicrosoftGraphUri, "/v1.0/users"));

        displayName = displayName.Replace("\\", "\\\\").Replace("\"", "\\\"");

        var query = HttpUtility.ParseQueryString(string.Empty);
        query["$select"] = _primaryUserProperties;
        query["$top"] = "15"; // limit the result to just several users
        query["$search"] = $"\"displayName:{displayName}\"";
        query["$filter"] = _userAccountEnabledFilter;
        requestUrlBuilder.Query = query.ToString();

        return await GetByIdAsync<UserResponse>(client, requestUrlBuilder.Uri, PreferModernSearchHeaders) ?? new UserResponse();
    }

    //https://learn.microsoft.com/en-us/graph/api/directoryobject-checkmembergroups?view=graph-rest-1.0&tabs=http
    /// <inheritdoc/>
    public async Task<GroupResponse> GetUserMembershipInGroups(string userId, IEnumerable<string> groupIdFilter)
    {
        ArgumentException.ThrowIfNullOrEmpty(userId);

        if (groupIdFilter == null || !groupIdFilter.Any())
        {
            return new GroupResponse();
        }

        var groupIds = groupIdFilter.Distinct(StringComparer.OrdinalIgnoreCase).ToArray();
        const int batchSize = 20;
        string relativeUrl = $"/v1.0/users/{userId}/checkMemberGroups";
        var client = CreateClient();
        var requestUrl = new Uri(client.BaseAddress ?? Constants.MicrosoftGraphUri, relativeUrl);

        var batches = groupIds.Chunk(batchSize).ToArray();

        var tasks = new List<Task<CheckMemberGroupsResponse?>>();

        foreach (var batch in batches)
        {
            var requestBody = new { groupIds = batch };
            var request = new HttpRequestMessage(HttpMethod.Post, requestUrl)
            {
                Content = JsonContent.Create(requestBody)
            };

            tasks.Add(SendAsync<CheckMemberGroupsResponse?>(client, request));
        }

        var results = await Task.WhenAll(tasks);

        var resultGroupIds = results.SelectMany(ids => ids == null ? Enumerable.Empty<string>() : ids.Value).ToList();

        return new GroupResponse
        {
            Groups = resultGroupIds.Select(id => new Group { Id = id }).ToList()
        };
    }

    private sealed class CheckMemberGroupsResponse
    {
        public string[] Value { get; set; } = [];
    }
}
