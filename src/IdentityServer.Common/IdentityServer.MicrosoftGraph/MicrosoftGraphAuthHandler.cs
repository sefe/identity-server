using System.Net.Http.Headers;
using Microsoft.Identity.Client;

namespace IdentityServer.MicrosoftGraph;

internal class MicrosoftGraphAuthHandler : DelegatingHandler
{
    private static readonly string[] _defaultScopes = { "https://graph.microsoft.com/.default" };

    private readonly IConfidentialClientApplication _confidentialClientApplication;

    public MicrosoftGraphAuthHandler(IConfidentialClientApplication confidentialClientApplication)
    {
        _confidentialClientApplication = confidentialClientApplication;
    }

    protected override async Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken)
    {
        var token = await GetAccessToken();
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", token);
        return await base.SendAsync(request, cancellationToken);
    }

    private async Task<string> GetAccessToken()
    {
        var result = await _confidentialClientApplication.AcquireTokenForClient(_defaultScopes).ExecuteAsync();
        string accessToken = result.AccessToken;
        return accessToken;
    }
}
