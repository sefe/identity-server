// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

using Duende.IdentityServer.Configuration;
using Duende.IdentityServer.Extensions;
using Duende.IdentityServer.Models;
using Duende.IdentityServer.Validation;
using IdentityServer.Abstraction.Extensions;

namespace IdentityServer.Services.Validation;

/// <summary>
/// Allow any port on loopback URIs, but strict validation for other URIs.
/// </summary>
public class LoopbackDynamicPortRedirectUriValidator : StrictRedirectUriValidator
{
    private readonly ILogger _logger;

    public LoopbackDynamicPortRedirectUriValidator(ILogger<LoopbackDynamicPortRedirectUriValidator> logger, IdentityServerOptions options) : base(options)
    {
        _logger = logger;
    }

    public override Task<bool> IsRedirectUriValidAsync(string requestedUri, Client client)
    {
        return Task.FromResult(IsRedirectUriValidSharedImpl(requestedUri, client.RedirectUris, client.ClientId, false));
    }

    public override Task<bool> IsPostLogoutRedirectUriValidAsync(string requestedUri, Client client)
    {
        return Task.FromResult(IsRedirectUriValidSharedImpl(requestedUri, client.PostLogoutRedirectUris, client.ClientId, true));
    }

#pragma warning disable IDE0079 // Remove unnecessary suppression
#pragma warning disable CA2254 // Template should be a static expression
#pragma warning disable S2629 // Don't use string interpolation in logging message templates.
    private bool IsRedirectUriValidSharedImpl(string requestedUri, ICollection<string> registeredUris, string clientId, bool isPostLogoutRedirectUri)
    {
        if (registeredUris.Count == 0)
        {
            return false;
        }

        if (!Uri.TryCreate(requestedUri, UriKind.Absolute, out var actualUri))
        {
            return false;
        }

        var uriLoggedName = isPostLogoutRedirectUri ? "Post-Logout Redirect URI" : "Redirect URI";
        var uriLoggedParameterName = isPostLogoutRedirectUri ? "{RequestedPostLogoutRedirectUri}" : "{RequestedRedirectUri}";

        if (!actualUri.IsLoopbackUri())
        {
            // log insecure protocol usage for non-loopback address
            if (actualUri.Scheme == Uri.UriSchemeHttp)
            {
                _logger.LogWarning($"Insecure HTTP {uriLoggedName} is used by {{ClientId}}: {uriLoggedParameterName}", clientId, requestedUri);
            }

            return StringCollectionContainsString(registeredUris, requestedUri);
        }

        var isValidLocalRedirect = IsLoopbackRedirectUriRegistered(actualUri, registeredUris);
        _logger.LogDebug($"Loopback {uriLoggedName} validation {{Status}} for client {{ClientId}}: {uriLoggedParameterName}", isValidLocalRedirect ? "succeeded" : "failed", clientId, requestedUri);

        return isValidLocalRedirect;
    }
#pragma warning restore S2629 // Don't use string interpolation in logging message templates.
#pragma warning restore CA2254 // Template should be a static expression
#pragma warning restore IDE0079 // Remove unnecessary suppression

    protected new bool StringCollectionContainsString(IEnumerable<string> uris, string requestedUri)
    {
        if (IEnumerableExtensions.IsNullOrEmpty(uris)) { return false; }

        return uris.Contains(requestedUri);
    }

    /// <summary>
    /// Matches the actual URI against the registered URIs ignoring port. Only for loopback URIs.
    /// </summary>
    /// <param name="actualUri">Requested Redirect URI</param>
    /// <param name="registeredUris">Registered Redirect URIs</param>
    /// <returns>True if matched.</returns>
    private bool IsLoopbackRedirectUriRegistered(Uri actualUri, ICollection<string> registeredUris)
    {
        foreach (var registeredUri in registeredUris)
        {
            if (!Uri.TryCreate(registeredUri, UriKind.Absolute, out var regUri))
            {
                _logger.LogDebug("Invalid registered Redirect URI: {RedirectUri}", registeredUri);
                continue;
            }

            var actualUriToCompare = actualUri.OriginalString;

            // remove the port from the actual URI if there is no original port specified
            if (regUri.IsDynamicPortAllowed() && !actualUri.IsDynamicPortAllowed())
            {
                actualUriToCompare = actualUriToCompare.ReplaceJustOnce($":{actualUri.Port}", string.Empty);
            }

            if (string.Equals(actualUriToCompare, registeredUri, StringComparison.Ordinal))
            {
                return true;
            }
        }

        return false;
    }
}
