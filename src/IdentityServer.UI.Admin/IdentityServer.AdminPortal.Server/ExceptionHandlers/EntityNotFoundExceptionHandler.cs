// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

using Microsoft.AspNetCore.Mvc;
using IdentityServer.Abstraction.Exceptions;
using IdentityServer.Core.Infrastructure;

namespace IdentityServer.AdminPortal.Server.ExceptionHandlers;

public class EntityNotFoundExceptionHandler : BasicExceptionHandler<EntityNotFoundException>
{
    public EntityNotFoundExceptionHandler(IProblemDetailsService problemDetailsService, ILogger<EntityNotFoundExceptionHandler> logger)
        : base(problemDetailsService, logger)
    {
    }

    protected override ProblemDetails CreateProblemDetails(HttpContext httpContext, EntityNotFoundException specificException)
    {
        return new ProblemDetails
        {
            Status = StatusCodes.Status404NotFound,
            Title = "The requested entity was not found",
            Detail = specificException.Message,
        };
    }
}
