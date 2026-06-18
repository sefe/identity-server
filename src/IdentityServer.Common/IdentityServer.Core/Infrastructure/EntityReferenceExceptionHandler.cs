using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Extensions.Logging;
using IdentityServer.Abstraction.Exceptions;

namespace IdentityServer.Core.Infrastructure;

public class EntityReferenceExceptionHandler : BasicExceptionHandler<EntityReferenceException>
{
    public EntityReferenceExceptionHandler(IProblemDetailsService problemDetailsService, ILogger<EntityReferenceExceptionHandler> logger)
        : base(problemDetailsService, logger)
    {
    }

    protected override ProblemDetails CreateProblemDetails(HttpContext httpContext, EntityReferenceException specificException)
    {
        return new ProblemDetails
        {
            Status = StatusCodes.Status400BadRequest,
            Title = "Invalid operation",
            Detail = specificException.Message,
        };
    }
}
