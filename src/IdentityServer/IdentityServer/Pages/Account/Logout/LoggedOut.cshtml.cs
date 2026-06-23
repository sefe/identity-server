// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

using Duende.IdentityServer.Services;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.RazorPages;

namespace IdentityServer.Pages.Account.Logout;

[SecurityHeaders]
[AllowAnonymous]
public class LoggedOut : PageModel
{
    private readonly IIdentityServerInteractionService _interactionService;

    public LoggedOutViewModel View { get; set; } = default!;

    public LoggedOut(IIdentityServerInteractionService interactionService)
    {
        _interactionService = interactionService;
    }

    public async Task<IActionResult> OnGetAsync(string? logoutId)
    {
        // get context information (client name, post logout redirect URI and iframe for federated signout)
        var logout = await _interactionService.GetLogoutContextAsync(logoutId);

        View = new LoggedOutViewModel
        {
            AutomaticRedirectAfterSignOut = LogoutOptions.AutomaticRedirectAfterSignOut,
            PostLogoutRedirectUri = logout?.PostLogoutRedirectUri,
            ClientName = string.IsNullOrEmpty(logout?.ClientName) ? logout?.ClientId : logout.ClientName,
            SignOutIframeUrl = logout?.SignOutIFrameUrl
        };

        // server-side redirection if post logout redirect URI is set
        if (!string.IsNullOrWhiteSpace(View.PostLogoutRedirectUri))
        {
            return Redirect(View.PostLogoutRedirectUri);
        }

        return Page();
    }
}
