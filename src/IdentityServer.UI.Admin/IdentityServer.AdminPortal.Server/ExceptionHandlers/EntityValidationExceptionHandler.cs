// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

using Microsoft.AspNetCore.Mvc;
using IdentityServer.Abstraction.Exceptions;
using IdentityServer.Core.Infrastructure;

namespace IdentityServer.AdminPortal.Server.ExceptionHandlers;

public class EntityValidationExceptionHandler : BasicExceptionHandler<EntityValidationException>
{
    public EntityValidationExceptionHandler(IProblemDetailsService problemDetailsService, ILogger<EntityValidationExceptionHandler> logger)
        : base(problemDetailsService, logger)
    {
    }

    protected override ProblemDetails CreateProblemDetails(HttpContext httpContext, EntityValidationException specificException)
    {
        return new ProblemDetails
        {
            Status = StatusCodes.Status400BadRequest,
            Title = "Entity is invalid",
            Detail = specificException.Message,
        };
    }

}
