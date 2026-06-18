using System.Net;

namespace IdentityServer.Tests.Common;

public class MockHttpMessageHandler : HttpMessageHandler
{
    private string _response;
    private HttpStatusCode _statusCode;
    private readonly Func<HttpRequestMessage, HttpResponseMessage> _responseFunc;
    private readonly bool _withValidResponse = true;
    public List<CapturedRequest> CapturedRequests { get; } = new();

    /// <summary>
    /// Mandatory follow-up with <see cref="SetResponse(HttpStatusCode, string)"/>
    /// </summary>
    public MockHttpMessageHandler()
    {
    }

    public MockHttpMessageHandler(HttpStatusCode statusCode, string response)
    {
        _response = response;
        _statusCode = statusCode;
    }

    public MockHttpMessageHandler(HttpStatusCode statusCode, bool withValidResponse)
    {
        _statusCode = statusCode;
        _withValidResponse = withValidResponse;
    }

    public MockHttpMessageHandler(HttpStatusCode statusCode, object response)
    {
        _response = System.Text.Json.JsonSerializer.Serialize(response);
        _statusCode = statusCode;
    }

    public MockHttpMessageHandler(Func<HttpRequestMessage, HttpResponseMessage> responseFunc)
    {
        _responseFunc = responseFunc;
    }

    public void SetResponse(HttpStatusCode statusCode, string response)
    {
        _response = response;
        _statusCode = statusCode;
    }

    protected override async Task<HttpResponseMessage> SendAsync(HttpRequestMessage request,
        CancellationToken cancellationToken)
    {
        var capturedRequest = new CapturedRequest
        {
            Url = request.RequestUri?.OriginalString,
            Method = request.Method,
            Headers = request.Headers.ToDictionary(h => h.Key, h => string.Join(", ", h.Value)),
            Body = request.Content != null ? await request.Content.ReadAsStringAsync(cancellationToken) : null
        };

        CapturedRequests.Add(capturedRequest);

        if (_responseFunc != null)
        {
            return _responseFunc(request);
        }
        else if (!_withValidResponse)
        {
            return new HttpResponseMessage
            {
                StatusCode = _statusCode,
                Content = new FailingHttpContent()
            };
        }
        else if (_response != null)
        {
            return new HttpResponseMessage
            {
                StatusCode = _statusCode,
                Content = new StringContent(_response)
            };
        }
        else
        {
            throw new InvalidOperationException("No response configured for the mock handler.");
        }
    }
}

public class CapturedRequest
{
    public string Url { get; set; }
    public HttpMethod Method { get; set; }
    public Dictionary<string, string> Headers { get; set; } = new();
    public string Body { get; set; }
}

internal class FailingHttpContent : HttpContent
{
    protected override Task SerializeToStreamAsync(Stream stream, TransportContext context)
    {
        return Task.CompletedTask;
    }

    protected override Task<Stream> CreateContentReadStreamAsync()
    {
        throw new InvalidOperationException("Simulated failure during content serialization.");
    }
    protected override bool TryComputeLength(out long length)
    {
        length = 0;
        return true;
    }
}
