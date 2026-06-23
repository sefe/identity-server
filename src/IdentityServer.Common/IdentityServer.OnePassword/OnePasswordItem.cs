// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

using System.Text.Json.Serialization;

namespace IdentityServer.OnePassword;

public class OnePasswordItem
{
    public const string CredentialCategory = "API_CREDENTIAL";
    public const string LoginCategory = "LOGIN";

    [JsonPropertyName("id")]
    public string Id { get; set; } = string.Empty;

    [JsonPropertyName("category")]
    public string Category { get; set; } = string.Empty;

    [JsonPropertyName("title")]
    public string Title { get; set; } = string.Empty;

    [JsonPropertyName("fields")]
    public List<OnePasswordField> Fields { get; set; } = new();

    public string? GetFieldValue(string fieldId)
    {
        return Fields.FirstOrDefault(f => f.Id == fieldId)?.Value;
    }
}
