// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

namespace IdentityServer.Abstraction.Exceptions;

public class EntityValidationException : Exception
{
    public EntityValidationException() { }

    public EntityValidationException(string message) : base(message) { }

    public EntityValidationException(string message, Exception inner) : base(message, inner) { }
}
