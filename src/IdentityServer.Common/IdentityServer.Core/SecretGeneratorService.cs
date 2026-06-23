// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

using System.Security.Cryptography;
using IdentityServer.Abstraction.Contracts;

namespace IdentityServer.Core;

public class SecretGeneratorService : ISecretGeneratorService
{
    public string GenerateSecureSecret()
    {
        using var randomNumberGenerator = RandomNumberGenerator.Create();
        byte[] secretBytes = new byte[64]; // 512 bits
        randomNumberGenerator.GetBytes(secretBytes);
        return Convert.ToBase64String(secretBytes);
    }
}
