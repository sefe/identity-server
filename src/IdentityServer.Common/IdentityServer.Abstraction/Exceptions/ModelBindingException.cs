// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

namespace IdentityServer.Abstraction.Exceptions;

public class ModelBindingException : Exception
{
    public ModelBindingException()
    {
    }

    public ModelBindingException(string? message) : base(message)
    {
    }

    public ModelBindingException(string? message, Exception? innerException) : base(message, innerException)
    {
    }
}
