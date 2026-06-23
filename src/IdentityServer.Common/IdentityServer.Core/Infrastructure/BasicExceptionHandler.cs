// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

using Microsoft.AspNetCore.Diagnostics;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Extensions.Logging;

namespace IdentityServer.Core.Infrastructure;

public abstract class BasicExceptionHandler : IExceptionHandler
{
    protected readonly ILogger _logger;
    protected readonly IProblemDetailsService _problemDetailsService;

    protected BasicExceptionHandler(IProblemDetailsService problemDetailsService, ILogger logger)
    {
        _logger = logger;
        _problemDetailsService = problemDetailsService;
    }

    public abstract ValueTask<bool> TryHandleAsync(HttpContext httpContext, Exception exception, CancellationToken cancellationToken);

    protected static string GetRequestPath(HttpContext httpContext)
    {
        var pathFeature = httpContext.Features.Get<IExceptionHandlerPathFeature>();
        var originalPath = pathFeature?.Path; // httpContext.Request.Path might get overwritten with /error by the middlware
        return originalPath ?? httpContext.Request.Path;
    }
}

public abstract class BasicExceptionHandler<TEx> : BasicExceptionHandler where TEx : Exception
{
    protected BasicExceptionHandler(IProblemDetailsService problemDetailsService, ILogger logger) : base(problemDetailsService, logger) { }

    public override ValueTask<bool> TryHandleAsync(HttpContext httpContext, Exception exception, CancellationToken cancellationToken)
    {
        if (exception is not TEx specificException) { return ValueTask.FromResult(false); }

        _logger.LogWarning(
                specificException,
                "Invalid {Method} Request at {Path}",
                httpContext.Request.Method, GetRequestPath(httpContext));

        var context = new ProblemDetailsContext
        {
            HttpContext = httpContext,
            Exception = exception,
            ProblemDetails = CreateProblemDetails(httpContext, specificException)
        };

        context.ProblemDetails.Instance = httpContext.TraceIdentifier;

        var statusCode = context.ProblemDetails.Status ?? StatusCodes.Status500InternalServerError;
        httpContext.Response.StatusCode = statusCode;
        context.ProblemDetails.Status = statusCode;

        return _problemDetailsService.TryWriteAsync(context);
    }

    /// <summary>
    /// Produces a detailed problem description.
    /// Make sure to populate <see cref="ProblemDetails.Status"/>, <see cref="ProblemDetails.Title"/>, and <see cref="ProblemDetails.Detail"/> members in the derived class.
    /// </summary>
    /// <remarks> Defaults will be used for missing members by <seealso cref="IProblemDetailsService"/>.</remarks>
    /// <param name="httpContext">Http Context</param>
    /// <param name="specificException">Exception object</param>
    /// <returns>Detailed problem description</returns>
    protected abstract ProblemDetails CreateProblemDetails(HttpContext httpContext, TEx specificException);
}
