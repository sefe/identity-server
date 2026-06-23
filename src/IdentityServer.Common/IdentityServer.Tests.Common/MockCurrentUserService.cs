// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

using IdentityServer.Abstraction;

namespace IdentityServer.Tests.Common;

public class MockCurrentUserService : ICurrentUserService
{
    private readonly string _username;

    public MockCurrentUserService() { }

    public MockCurrentUserService(string username)
    {
        _username = username;
    }

    public string UserName => _username  ?? "testuser";
}
