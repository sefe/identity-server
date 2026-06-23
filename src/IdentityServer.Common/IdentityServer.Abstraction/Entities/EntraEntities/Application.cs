// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

using System.Text.Json.Serialization;
using IdentityServer.Abstraction.Contracts;

namespace IdentityServer.Abstraction.Entities.EntraEntities;

public class Application : IHasId<string>
{
    [JsonPropertyName("id")]
    public required string Id { get; set; }

    [JsonPropertyName("appId")]
    public required string AppId { get; set; }

    [JsonPropertyName("displayName")]
    public string DisplayName { get; set; } = string.Empty;

    // Add other properties as needed
    //https://learn.microsoft.com/en-us/graph/api/application-get?view=graph-rest-1.0&tabs=http
}
