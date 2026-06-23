// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

using System.Net;

namespace IdentityServer.Tests.Common;

public class MockHttpMultiMessageHandler : HttpMessageHandler
{
    private readonly List<(HttpStatusCode StatusCode, object Response)> _responses;

    public List<CapturedRequest> CapturedRequests { get; } = new();

    public MockHttpMultiMessageHandler(List<(HttpStatusCode StatusCode, object Response)> responses)
    {
        _responses = responses ?? throw new ArgumentNullException(nameof(responses));
    }

    protected override async Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken)
    {
        var capturedRequest = new CapturedRequest
        {
            Url = request.RequestUri?.OriginalString,
            Method = request.Method,
            Headers = request.Headers.ToDictionary(h => h.Key, h => string.Join(", ", h.Value)),
            Body = request.Content != null ? await request.Content.ReadAsStringAsync(cancellationToken) : null
        };

        CapturedRequests.Add(capturedRequest);

        if (CapturedRequests.Count > _responses.Count)
        {
            // a default response if we run out of configured responses
            return new HttpResponseMessage
            {
                StatusCode = HttpStatusCode.OK,
                Content = new StringContent("{}")
            };
        }

        var response = _responses[CapturedRequests.Count - 1];
        var serializedObject = System.Text.Json.JsonSerializer.Serialize(response.Response);
        return new HttpResponseMessage
        {
            StatusCode = response.StatusCode,
            Content = new StringContent(serializedObject)
        };
    }
}
