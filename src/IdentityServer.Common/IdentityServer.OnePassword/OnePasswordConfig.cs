// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

namespace IdentityServer.OnePassword;

/// <summary>
/// Config to retrieve secrets from 1Password using specified <see cref="AccessToken"/>.
/// One token can be used to access multiple vaults (as configured upon token creation).
/// </summary>
public class OnePasswordConfig
{
    public required string BaseUrl { get; set; }
    public required string AccessToken { get; set; }
    public required string VaultId { get; set; }

    /// <summary>
    /// Dictionary where key is the target config section path (if used on startup to amend application configuration and any app-recognized secret identifier otherwise) and value is the secret id to retrieve.
    /// </summary>
    public required Dictionary<string, string> Secrets { get; set; }
}
