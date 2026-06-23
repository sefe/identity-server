// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Extensions.Logging;
using IdentityServer.Abstraction.Exceptions;

namespace IdentityServer.Core.Infrastructure;

public class ModelBindingExceptionHandler : BasicExceptionHandler<ModelBindingException>
{
    public ModelBindingExceptionHandler(IProblemDetailsService problemDetailsService, ILogger<ModelBindingExceptionHandler> logger)
        : base(problemDetailsService, logger)
    {
    }

    protected override ProblemDetails CreateProblemDetails(HttpContext httpContext, ModelBindingException specificException)
    {
        return new ProblemDetails
        {
            Status = StatusCodes.Status400BadRequest,
            Title = "Unable to process the submitted data.",
            Detail = specificException.Message,
        };
    }
}
