// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

namespace IdentityServer.Pages.Account.Logout;

public class LoggedOutViewModel
{
    public string? PostLogoutRedirectUri { get; set; }
    public string? ClientName { get; set; }
    public string? SignOutIframeUrl { get; set; }
    public bool AutomaticRedirectAfterSignOut { get; set; }
}
