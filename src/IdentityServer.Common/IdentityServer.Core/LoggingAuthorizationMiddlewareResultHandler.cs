// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Authorization.Policy;
using Microsoft.AspNetCore.Http;
using Microsoft.Extensions.Logging;

namespace IdentityServer.Core;

public class LoggingAuthorizationMiddlewareResultHandler : IAuthorizationMiddlewareResultHandler
{
    private readonly AuthorizationMiddlewareResultHandler _defaultHandler = new();
    private readonly ILogger<LoggingAuthorizationMiddlewareResultHandler> _logger;

    public LoggingAuthorizationMiddlewareResultHandler(ILogger<LoggingAuthorizationMiddlewareResultHandler> logger)
    {
        _logger = logger;
    }

    public async Task HandleAsync(
        RequestDelegate next,
        HttpContext context,
        AuthorizationPolicy policy,
        PolicyAuthorizationResult authorizeResult)
    {
        if (!authorizeResult.Succeeded)
        {

            _logger.LogWarning("Authorization failed ({ResponseCode}). Path: {Path}, User: {User}, Policy: {Policy}.",
                authorizeResult.Challenged ? "401" : "403",
                context.Request.Path,
                context.User?.Identity?.Name ?? "Anonymous",
                string.Join(", ", policy.Requirements.Select(r => r.ToString()))
            );
        }

        await _defaultHandler.HandleAsync(next, context, policy, authorizeResult);
    }
}
