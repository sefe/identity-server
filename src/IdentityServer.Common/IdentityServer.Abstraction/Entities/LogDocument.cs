using System.Text.Json.Serialization;

namespace IdentityServer.Abstraction.Entities
{
    public class LogDocument
    {
        [JsonPropertyName("message")]
        public required string Message { get; set; }

        [JsonPropertyName("log.level")]
        public required string Level { get; set; }

        [JsonPropertyName("@timestamp")]
        public DateTime Timestamp { get; set; }

        [JsonPropertyName("trading.system.component_name")]
        public string? ComponentName { get; set; }

    }
}
