// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

namespace IdentityServer.Abstraction.Exceptions;

public class IdentityServerException : Exception
{
    public IdentityServerException() { }

    public IdentityServerException(string message) : base(message) { }

    public IdentityServerException(string message, Exception inner) : base(message, inner) { }
}
