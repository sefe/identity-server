// Copyright (c) Duende Software. All rights reserved.
// See LICENSE in the project root for license information.

using Duende.IdentityServer;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc.RazorPages;
using IdentityServer.Abstraction;

namespace IdentityServer.Pages;

[AllowAnonymous]
public class Index : PageModel
{
    public Index(IdentityServerLicense? license = null)
    {
        License = license;
    }

    public static string GetVersion()
    {
        var version = CommonHelpers.GetEntryAssemblyVersion();
        return version ?? "";
    } 

    public IdentityServerLicense? License { get; }
}
