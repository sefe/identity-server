// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

using System.Text.Json.Serialization;

namespace IdentityServer.Abstraction.Entities.EntraEntities;

public class UserResponse
{
    // example - https://graph.microsoft.com/v1.0/$metadata#directoryObjects
    [JsonPropertyName("@odata.context")]
    public string? Context { get; set; }

    [JsonPropertyName("@odata.nextLink")]
    public string? NextLink { get; set; }

    /// <summary>
    /// Extracted from NextLink if available.
    /// </summary>
    public string? SkipToken { get; set; }

    [JsonPropertyName("value")]
    public List<User> Users { get; set; } = [];
}