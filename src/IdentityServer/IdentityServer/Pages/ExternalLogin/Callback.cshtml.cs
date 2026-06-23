// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

using System.Security.Claims;
using Duende.IdentityModel;
using Duende.IdentityServer;
using Duende.IdentityServer.Events;
using Duende.IdentityServer.Services;
using Microsoft.AspNetCore.Authentication;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.RazorPages;
using IdentityServer.Abstraction.Exceptions;
using static IdentityServer.Abstraction.Constants;

namespace IdentityServer.Pages.ExternalLogin;

[AllowAnonymous]
[SecurityHeaders]
public class Callback : PageModel
{
    private readonly IIdentityServerInteractionService _interaction;
    private readonly ILogger<Callback> _logger;
    private readonly IEventService _events;

    public Callback(
        IIdentityServerInteractionService interaction,
        IEventService events,
        ILogger<Callback> logger)
    {
        _interaction = interaction;
        _logger = logger;
        _events = events;
    }

    public async Task<IActionResult> OnGet()
    {
        // read external identity from the temporary cookie
        bool hasExternalCookie = HttpContext.Request.Cookies.ContainsKey(IdentityServerConstants.ExternalCookieAuthenticationScheme);
        if (!hasExternalCookie)
        {
            throw new UserAuthenticationException($"External authentication error: no {IdentityServerConstants.ExternalCookieAuthenticationScheme} cookie present");
        }

        var result = await HttpContext.AuthenticateAsync(IdentityServerConstants.ExternalCookieAuthenticationScheme);
        if (!result.Succeeded)
        {
            if (result.None)
            {
                // this means the user did not complete the external authentication
                throw new UserAuthenticationException("External authentication was not completed.");
            }
            throw new UserAuthenticationException($"External authentication error: {result.Failure}", result.Failure ?? new Exception("Unknown error"));
        }

        var externalUser = result.Principal ??
            throw new InvalidOperationException("External authentication produced a null Principal");

        if (_logger.IsEnabled(LogLevel.Debug))
        {
            var externalClaims = externalUser.Claims.Select(c => $"{c.Type}: {c.Value}");
            _logger.ExternalClaims(externalClaims);
        }

        // lookup our user and external provider info
        // try to determine the unique id of the external user (issued by the provider)
        // the most common claim type for that are the sub claim and the NameIdentifier
        // depending on the external provider, some other claim type might be used
        var userIdClaim = externalUser.FindFirst(ClaimNames.UserObjectId) ??
                          externalUser.FindFirst(ClaimTypes.NameIdentifier) ??
                          throw new InvalidOperationException("Unknown userid");

        // extract user name
        var username = ExtractUserNameFromClaims(externalUser);

        var provider = result.Properties.Items["scheme"] ?? throw new InvalidOperationException("Null scheme in authentication properties");
        var providerUserId = userIdClaim.Value;

        // this allows us to collect any additional claims or properties
        // for the specific protocols used and store them in the local auth cookie.
        // this is typically used to store data needed for signout from those protocols.
        var additionalLocalClaims = new List<Claim>();
        var localSignInProps = new AuthenticationProperties();
        CaptureExternalLoginContext(result, additionalLocalClaims, localSignInProps);

        // issue authentication cookie for user
        var isuser = new IdentityServerUser(userIdClaim.Value)
        {
            DisplayName = username,
            IdentityProvider = provider,
            AdditionalClaims = additionalLocalClaims
        };

        await HttpContext.SignInAsync(isuser, localSignInProps);

        // delete temporary cookie used during external authentication
        await HttpContext.SignOutAsync(IdentityServerConstants.ExternalCookieAuthenticationScheme);

        // retrieve return URL
        var returnUrl = result.Properties.Items["returnUrl"] ?? "~/";

        // check if external login is in the context of an OIDC request
        var context = await _interaction.GetAuthorizationContextAsync(returnUrl);
        await _events.RaiseAsync(new UserLoginSuccessEvent(provider, providerUserId, userIdClaim.Value, username, true, context?.Client.ClientId));
        Telemetry.Metrics.TrackUserLogin(context?.Client.ClientId, provider!);

        if (context != null && context.IsNativeClient())
        {
            // The client is native, so this change in how to
            // return the response is for better UX for the end user.
            return this.LoadingPage(returnUrl);
        }

        return Redirect(returnUrl);
    }

    private static string ExtractUserNameFromClaims(ClaimsPrincipal externalUser)
    {
        var userNameClaim = externalUser.FindFirst(JwtClaimTypes.Name);
        if (userNameClaim != null)
        {
            return userNameClaim.Value;
        }
        else
        {
            var first = externalUser.FindFirst(x => x.Type == JwtClaimTypes.GivenName)?.Value;
            var last = externalUser.FindFirst(x => x.Type == JwtClaimTypes.FamilyName)?.Value;
            if (first != null && last != null)
            {
                return first + " " + last;
            }
            else if (first != null)
            {
                return first;
            }
            else if (last != null)
            {
                return last;
            }
        }

        return "Unknown User";
    }

    // if the external login is OIDC-based, there are certain things we need to preserve to make logout work
    // this will be different for WS-Fed, SAML2p or other protocols
    private static void CaptureExternalLoginContext(AuthenticateResult externalResult, List<Claim> localClaims, AuthenticationProperties localSignInProps)
    {
        ArgumentNullException.ThrowIfNull(externalResult.Principal);

        // capture the idp used to login, so the session knows where the user came from
        localClaims.Add(new Claim(JwtClaimTypes.IdentityProvider, externalResult.Properties?.Items["scheme"] ?? "unknown identity provider"));

        // if the external system sent a session id claim, copy it over
        // so we can use it for single sign-out
        var sid = externalResult.Principal.Claims.FirstOrDefault(x => x.Type == JwtClaimTypes.SessionId);
        if (sid != null)
        {
            localClaims.Add(new Claim(JwtClaimTypes.SessionId, sid.Value));
        }

        // if the external provider issued an id_token, we'll keep it for signout
        var idToken = externalResult.Properties?.GetTokenValue("id_token");
        if (idToken != null)
        {
            localSignInProps.StoreTokens(new[] { new AuthenticationToken { Name = "id_token", Value = idToken } });
        }

        //ObjectId (oid) is the immutable identifier for the requestor, which is the verified identity of the user or service principal.
        //This ID uniquely identifies the requestor across applications.
        var oid = externalResult.Principal.FindFirst(ClaimNames.UserObjectId);
        if (oid != null)
        {
            localClaims.Add(oid);
        }

        //User Principal Name (upn) is the username of the user.
        //May be a phone number, email address, or unformatted string.
        //Only use for display purposes and providing username hints in reauthentication scenarios.
        //Only use for display purposes and providing username hints in reauthentication scenarios.
        var upn = externalResult.Principal.FindFirst(ClaimNames.UserPrincipalName);
        if (upn != null)
        {
            localClaims.Add(upn);
        }

        //Email
        var email = externalResult.Principal.FindFirst(ClaimNames.UserEmail);
        if (email != null)
        {
            localClaims.Add(email);
        }
    }
}
