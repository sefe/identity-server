// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

namespace IdentityServer.Abstraction.Entities.IdentityServerConfig;

public static class OidcScopeNames
{
    public const string OpenIdScope = "openid";

    public static readonly IReadOnlyList<OidcScope> OidcStandardScopes = new List<OidcScope>
        {
            new() { Name = OpenIdScope,  Required = true, DisplayName = "Mandatory OpenID Connect protocol scope." },
            new() { Name ="profile", Required = false, DisplayName = "Access to the End-User's default profile claims." },
            new() { Name ="email", Required = false, DisplayName = "Access to the 'email' and 'email_verified' claims" },
            //new() { Name ="phone", Required = false, DisplayName = "Access to the 'phone_number' and 'phone_number_verified' claims." }, // disabled due to the bug #361969
            //new() { Name ="address", Required = false, DisplayName = "Access to the 'address' claim" }, // disabled due to the bug #361969
            // offline_access is managed by Client.AllowOfflineAccess property
        };

    public static readonly IReadOnlySet<string> OidcStandardScopeIds = OidcStandardScopes.Select(s => s.Name).ToHashSet();

    public static readonly IReadOnlyDictionary<string, OidcScope> OidcStandardScopeMapping = OidcStandardScopes.ToDictionary(s => s.Name);
}

public class OidcScope
{
    public string Name { get; set; } = default!;
    public bool Required { get; set; }
    public string DisplayName { get; set; } = default!;
}
