using Microsoft.Extensions.Logging;

namespace IdentityServer.MicrosoftGraph.Extensions;

public static class HttpResponseMessageExtensions
{
    public static async Task LogErrorResponseAsync(this HttpResponseMessage response, string method, Uri? requestUri, ILogger _logger)
    {
        _logger.LogError("MsGraph {MsGraphMethod} failed: {ResponseCode} {RequestUri}", method, response.StatusCode, requestUri);
        try
        {
            var content = await response.Content.ReadAsStringAsync();
            _logger.LogError("MsGraph {MsGraphMethod} failed response content: {Content}", method, content);
        }
        catch { /* ignore response reading errors */ }
    }
}
