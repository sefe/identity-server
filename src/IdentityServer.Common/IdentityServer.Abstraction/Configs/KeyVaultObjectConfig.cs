// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

namespace IdentityServer.Abstraction.Configs;

public class KeyVaultObjectConfig
{
    /// <summary>
    /// KeyVault URL where the object is stored.
    /// </summary>
    public required string KeyVaultUrl { get; set; }

    /// <summary>
    /// Name of the KeyVault object (object can be secret, key or certificate).
    /// Code using class instance must know type of the object (secret, key, certificate) to call corresponding KeyVault APIs.
    /// </summary>
    public required string ObjectName { get; set; }
}
