// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

using Microsoft.AspNetCore.Mvc;
using IdentityServer.Abstraction.Exceptions;
using IdentityServer.Core.Infrastructure;

namespace IdentityServer.AdminPortal.Server.ExceptionHandlers;

public class EntityAlreadyExistsExceptionHandler : BasicExceptionHandler<EntityAlreadyExistsException>
{
    public EntityAlreadyExistsExceptionHandler(IProblemDetailsService problemDetailsService, ILogger<EntityAlreadyExistsExceptionHandler> logger)
        : base(problemDetailsService, logger)
    {
    }

    protected override ProblemDetails CreateProblemDetails(HttpContext httpContext, EntityAlreadyExistsException specificException)
    {
        return new ProblemDetails
        {
            Status = StatusCodes.Status400BadRequest,
            Title = "Entity already exists",
            Detail = specificException.Message,
        };
    }
}
