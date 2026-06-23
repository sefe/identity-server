// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Extensions.Logging;
using IdentityServer.Abstraction.Exceptions;

namespace IdentityServer.Core.Infrastructure;

public class UserAuthenticationExceptionHandler : BasicExceptionHandler<UserAuthenticationException>
{
    public UserAuthenticationExceptionHandler(IProblemDetailsService problemDetailsService, ILogger<UserAuthenticationExceptionHandler> logger)
        : base(problemDetailsService, logger)
    {
    }

    protected override ProblemDetails CreateProblemDetails(HttpContext httpContext, UserAuthenticationException specificException)
    {
        return new ProblemDetails
        {
            Status = StatusCodes.Status400BadRequest,
            Title = "Invalid authentication data",
            Detail = specificException.Message,
        };
    }
}
