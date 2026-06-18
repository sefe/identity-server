using Microsoft.AspNetCore.Mvc;
using IdentityServer.Abstraction.Exceptions;
using IdentityServer.Core.Infrastructure;

namespace IdentityServer.AdminPortal.Server.ExceptionHandlers;

public class ImportValidationExceptionHandler : BasicExceptionHandler<ImportValidationException>
{
    public ImportValidationExceptionHandler(IProblemDetailsService problemDetailsService, ILogger<ImportValidationExceptionHandler> logger)
        : base(problemDetailsService, logger)
    {
    }

    protected override ProblemDetails CreateProblemDetails(HttpContext httpContext, ImportValidationException specificException)
    {
        return new ProblemDetails
        {
            Status = StatusCodes.Status400BadRequest,
            Title = "The import data is invalid.",
            Detail = specificException.Message,
        };
    }
}
