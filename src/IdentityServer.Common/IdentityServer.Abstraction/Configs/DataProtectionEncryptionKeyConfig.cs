// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

namespace IdentityServer.Abstraction.Configs;

public class DataProtectionEncryptionKeyConfig
{
    public string KeyVaultUrl { get; set; } = string.Empty;
    public string KeyName { get; set; } = string.Empty;
}