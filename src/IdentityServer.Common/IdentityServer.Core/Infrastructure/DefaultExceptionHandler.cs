// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Extensions.Logging;

namespace IdentityServer.Core.Infrastructure;

public class DefaultExceptionHandler : BasicExceptionHandler
{
    public DefaultExceptionHandler(IProblemDetailsService problemDetailsService, ILogger<DefaultExceptionHandler> logger) : base(problemDetailsService, logger) { }

    public override ValueTask<bool> TryHandleAsync(HttpContext httpContext, Exception exception, CancellationToken cancellationToken)
    {
        var requestPath = GetRequestPath(httpContext);
        // NB! unlike more specific handlers, this handler is for truly unhandled exceptions that should be looked at and investigated by the Team
        _logger.LogError(exception, "Unhandled exception occurred on {Method} Request at {Path}",
                httpContext.Request.Method, requestPath);

        var problemDetails = new ProblemDetails
        {
            Title = "Internal Server Error",
            Status = StatusCodes.Status500InternalServerError,
            Detail = $"An unexpected error occurred at {requestPath}. Provide Instance id to the Identity Server Support team for troubleshooting.",
            Instance = httpContext.TraceIdentifier
        };

        var context = new ProblemDetailsContext
        {
            HttpContext = httpContext,
            Exception = exception,
            ProblemDetails = problemDetails
        };

        httpContext.Response.StatusCode = StatusCodes.Status500InternalServerError;
        return _problemDetailsService.TryWriteAsync(context);
    }
}
