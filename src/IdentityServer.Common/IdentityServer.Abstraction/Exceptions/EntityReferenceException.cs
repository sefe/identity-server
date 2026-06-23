// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

namespace IdentityServer.Abstraction.Exceptions;

public class EntityReferenceException : Exception
{
    public EntityReferenceException() { }

    public EntityReferenceException(string message) : base(message) { }

    public EntityReferenceException(string message, Exception inner) : base(message, inner) { }
}
