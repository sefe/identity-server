// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

using Microsoft.Extensions.Logging;
using IdentityServer.Abstraction.Entities.EntraEntities;

namespace IdentityServer.MicrosoftGraph;

internal class MicrosoftGraphApplicationApiClient : MicrosoftGraphApiClientBase, IMicrosoftGraphApplicationApi
{
    protected override string ClientName => Constants.HttpClientNames.GraphApplicationsClientName;

    public MicrosoftGraphApplicationApiClient(IHttpClientFactory clientFactory, ILogger<MicrosoftGraphApplicationApiClient> logger)
        : base(clientFactory, logger)
    {
    }

    public Task<Application?> GetApplicationByAppIdAsync(string appId)
    {
        var relativePath = $"/v1.0/applications(appId='{appId}')?$select=id,appId,displayName";
        return GetByIdAsync<Application>(relativePath);
    }
}
