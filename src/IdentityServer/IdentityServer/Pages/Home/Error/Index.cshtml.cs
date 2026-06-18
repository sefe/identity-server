// Copyright (c) Duende Software. All rights reserved.
// See LICENSE in the project root for license information.

using Duende.IdentityServer.Services;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc.RazorPages;
using IdentityServer.Abstraction.Configs;
using IdentityServer.Pages.Error;

namespace IdentityServer.Pages.Home.Error;

[AllowAnonymous]
[SecurityHeaders]
public class Index : PageModel
{
    private readonly IIdentityServerInteractionService _interaction;

    public ViewModel View { get; set; } = new();

    public Index(IIdentityServerInteractionService interaction, ISystemConfig systemConfig)
    {
        _interaction = interaction;
        View.SupportEmailAddress = systemConfig.SupportEmailAddress;
    }

    public async Task OnGet(string? errorId)
    {
        // retrieve error details from identityserver
        var message = await _interaction.GetErrorContextAsync(errorId);
        if (message != null)
        {
            View.Error = message;
        }
    }
}
