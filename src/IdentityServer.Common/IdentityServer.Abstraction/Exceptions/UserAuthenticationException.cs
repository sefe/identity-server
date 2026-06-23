// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

namespace IdentityServer.Abstraction.Exceptions;

public class UserAuthenticationException : Exception
{
    public UserAuthenticationException() { }

    public UserAuthenticationException(string message) : base(message) { }

    public UserAuthenticationException(string message, Exception inner) : base(message, inner) { }
}
