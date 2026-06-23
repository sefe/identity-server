// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

namespace IdentityServer.Abstraction.Exceptions;

public class EntityAlreadyExistsException : Exception
{
    public EntityAlreadyExistsException() { }

    public EntityAlreadyExistsException(string message) : base(message) { }

    public EntityAlreadyExistsException(string message, Exception inner) : base(message, inner) { }
}
