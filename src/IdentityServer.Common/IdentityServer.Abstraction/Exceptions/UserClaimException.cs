// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

namespace IdentityServer.Abstraction.Exceptions;

public class UserClaimException : Exception
{
    public UserClaimException() { }

    public UserClaimException(string claimName, string message) : base(message)
    {
        ClaimName = claimName;
    }

    public UserClaimException(string claimName, string message, Exception inner) : base(message, inner)
    {
        ClaimName = claimName;
    }

    public string ClaimName { get; private set; } = string.Empty;
}
