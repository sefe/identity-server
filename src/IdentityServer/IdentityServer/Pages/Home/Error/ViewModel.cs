// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

using Duende.IdentityServer.Models;

namespace IdentityServer.Pages.Error;

public class ViewModel
{
    public ViewModel()
    {
    }

    public ViewModel(string error)
    {
        Error = new ErrorMessage { Error = error };
    }

    public ErrorMessage? Error { get; set; }

    public string? SupportEmailAddress { get; set; }

    public DateTimeOffset Timestamp { get; set; } = DateTimeOffset.UtcNow;

    public string GetMailLink()
    {
        var body = GetErrorMessage();
        return $"mailto:{SupportEmailAddress}?subject=[DIS] Client Auth Error Troubleshooting assistance&body={Uri.EscapeDataString(body)}";
    }

    public string GetErrorMessage()
    {
        if (Error == null)
        {
            return $"An unknown error has occurred at {Timestamp}";
        }
        else
        {
            return $"RequestId: {Error.RequestId}\n" +
                   $"ClientId: {Error.ClientId}\n" +
                   $"RedirectURI: {GetRedirectUri()}\n" +
                   $"Error: {Error.Error}\n" +
                   $"Description: {Error.ErrorDescription}\n" +
                   $"Timestamp: {Timestamp:u}" +
                   $"Activity ID: {Error.ActivityId}";
        }
    }

    public string GetRedirectUri()
    {
        // only take the base URI without query parameters to avoid exposing sensitive information if present
        var redirectUri = Error?.RedirectUri ?? string.Empty;
        if (!string.IsNullOrEmpty(redirectUri))
        {
            var paramsSeparator = redirectUri.IndexOf('?');
            redirectUri = paramsSeparator > -1
            ? redirectUri[..paramsSeparator]
            : redirectUri;
        }
        return redirectUri;
    }
}
