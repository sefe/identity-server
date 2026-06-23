// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

using Microsoft.AspNetCore.Http;
using IdentityServer.Abstraction;
using IdentityServer.Abstraction.Extensions;

namespace IdentityServer.Core;

public class CurrentUserService : ICurrentUserService
{
    private readonly IHttpContextAccessor _httpContextAccessor;

    public CurrentUserService(IHttpContextAccessor httpContextAccessor)
    {
        _httpContextAccessor = httpContextAccessor;
    }

    public string? UserName => _httpContextAccessor.HttpContext?.User.GetUserNameOrDefault();
}

