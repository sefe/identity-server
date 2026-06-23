// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

namespace IdentityServer.MicrosoftGraph;

public static class Constants
{
    public static readonly Uri MicrosoftGraphUri = new("https://graph.microsoft.com/");

    public static class HttpClientNames
    {
        public static readonly string GraphApplicationsClientName = "GraphApplicationClient";
        public static readonly string GraphGroupsClientName = "GraphGroupClient";
        public static readonly string GraphUsersClientName = "GraphUserClient";
    }
}
