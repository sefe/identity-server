using System.Text.Json.Serialization;

namespace IdentityServer.OnePassword;

public class OnePasswordField
{
    public const string CredentialFieldId = "credential";
    public const string PasswordFieldId = "password";

    [JsonPropertyName("id")]
    public string Id { get; set; } = string.Empty;

    [JsonPropertyName("type")]
    public string Type { get; set; } = string.Empty;

    [JsonPropertyName("label")]
    public string Label { get; set; } = string.Empty;

    [JsonPropertyName("value")]
    public string Value { get; set; } = string.Empty;
}
