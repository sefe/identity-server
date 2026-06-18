namespace IdentityServer.Core.Serilog.Entities;
public class HttpContextData
{
    public const string Alias = "Http";

    public string? HttpMethod { get; set; }

    public int? ResponseStatusCode { get; set; }

    public string? ClientIpAddress { get; set; }

    public string? RequestPath { get; set; }

    public string? Controller { get; set; }

    public string? Action { get; set; }
}
