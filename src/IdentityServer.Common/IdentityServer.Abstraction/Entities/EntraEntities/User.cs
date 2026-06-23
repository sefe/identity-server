// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

using System.Text.Json.Serialization;
using IdentityServer.Abstraction.Contracts;

namespace IdentityServer.Abstraction.Entities.EntraEntities;

public class User : IHasId<string>
{
    [JsonPropertyName("id")]
    public required string OId { get; set; }

    string IHasId<string>.Id
    {
        get { return OId ?? string.Empty; }
        set { OId = value; }
    }

    [JsonPropertyName("displayName")]
    public string DisplayName { get; set; } = string.Empty;

    [JsonPropertyName("accountEnabled")]
    public bool? AccountEnabled { get; set; }

    public override bool Equals(object? obj)
    {
        if (ReferenceEquals(this, obj)) { return true; }
        if (obj is not User other) { return false; }
        return string.Equals(OId, other.OId, StringComparison.OrdinalIgnoreCase);
    }

    public override int GetHashCode()
    {
        return (OId != null ? StringComparer.OrdinalIgnoreCase.GetHashCode(OId) : 0);
    }
}
