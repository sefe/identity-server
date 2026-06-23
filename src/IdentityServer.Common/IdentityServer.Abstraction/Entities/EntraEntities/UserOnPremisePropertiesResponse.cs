// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

using System.Text.Json.Serialization;

namespace IdentityServer.Abstraction.Entities.EntraEntities;

/// <summary>
/// A subset of properties from https://learn.microsoft.com/en-us/graph/api/resources/user?view=graph-rest-1.0
/// </summary>
public class UserOnPremisePropertiesResponse
{
    [JsonPropertyName("onPremisesSamAccountName")]
    public string? OnPremisesSamAccountName { get; set; }
}
