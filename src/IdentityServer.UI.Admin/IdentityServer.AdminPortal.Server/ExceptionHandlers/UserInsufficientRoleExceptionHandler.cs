// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

using Microsoft.AspNetCore.Mvc;
using IdentityServer.Abstraction.Exceptions;
using IdentityServer.Core.Infrastructure;

namespace IdentityServer.AdminPortal.Server.ExceptionHandlers;

public class UserInsufficientRoleExceptionHandler : BasicExceptionHandler<UserInsufficientRoleException>
{
    public UserInsufficientRoleExceptionHandler(IProblemDetailsService problemDetailsService, ILogger<UserInsufficientRoleExceptionHandler> logger)
        : base(problemDetailsService, logger)
    {
    }

    protected override ProblemDetails CreateProblemDetails(HttpContext httpContext, UserInsufficientRoleException specificException)
    {
        return new ProblemDetails
        {
            Status = StatusCodes.Status400BadRequest,
            Detail = specificException.Message,
            Title = "Insufficient user roles"
        };
    }
}
