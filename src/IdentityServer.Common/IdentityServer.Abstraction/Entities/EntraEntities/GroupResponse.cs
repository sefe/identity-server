// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

using System.Text.Json.Serialization;

namespace IdentityServer.Abstraction.Entities.EntraEntities;

public class GroupResponse
{
    [JsonPropertyName("value")]
    public List<Group> Groups { get; set; } = new();

    [JsonPropertyName("@odata.nextLink")]
    public string? NextLink { get; set; }

    /// <summary>
    /// Extracted from NextLink if available.
    /// </summary>
    public string? SkipToken { get; set; }

    [JsonPropertyName("@odata.context")]
    public string? Context { get; set; }
}