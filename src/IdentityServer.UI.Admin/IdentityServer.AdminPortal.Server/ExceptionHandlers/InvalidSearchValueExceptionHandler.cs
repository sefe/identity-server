// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

using Microsoft.AspNetCore.Mvc;
using IdentityServer.Abstraction.Exceptions;
using IdentityServer.Core.Infrastructure;

namespace IdentityServer.AdminPortal.Server.ExceptionHandlers;

public class InvalidSearchValueExceptionHandler : BasicExceptionHandler<InvalidSearchValueException>
{
    public InvalidSearchValueExceptionHandler(IProblemDetailsService problemDetailsService, ILogger<InvalidSearchValueExceptionHandler> logger)
        : base(problemDetailsService, logger)
    {
    }

    protected override ProblemDetails CreateProblemDetails(HttpContext httpContext, InvalidSearchValueException specificException)
    {
        return new ProblemDetails
        {
            Status = StatusCodes.Status400BadRequest,
            Title = "The provided search term is invalid",
            Detail = specificException.Message,
        };
    }
}
