// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

namespace IdentityServer.Abstraction.Exceptions;

public class UserInsufficientRoleException : Exception
{
    public UserInsufficientRoleException() { }

    public UserInsufficientRoleException(string message) : base(message) { }

    public UserInsufficientRoleException(string message, Exception inner) : base(message, inner) { }
}
