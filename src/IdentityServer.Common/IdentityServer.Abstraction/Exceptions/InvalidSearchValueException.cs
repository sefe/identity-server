// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

namespace IdentityServer.Abstraction.Exceptions;

public class InvalidSearchValueException : Exception
{
    public InvalidSearchValueException() { }

    public InvalidSearchValueException(string message) : base(message) { }

    public InvalidSearchValueException(string message, Exception inner) : base(message, inner) { }
}
