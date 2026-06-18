using Microsoft.AspNetCore.Mvc;
using IdentityServer.Abstraction.Exceptions;
using IdentityServer.Core.Infrastructure;

namespace IdentityServer.AdminPortal.Server.ExceptionHandlers;

public class EntityAccessExceptionHandler : BasicExceptionHandler<EntityAccessException>
{
    public EntityAccessExceptionHandler(IProblemDetailsService problemDetailsService, ILogger<EntityAccessExceptionHandler> logger)
        : base(problemDetailsService, logger)
    {
    }

    protected override ProblemDetails CreateProblemDetails(HttpContext httpContext, EntityAccessException specificException)
    {
        return new ProblemDetails
        {
            Status = StatusCodes.Status403Forbidden,
            Title = "The user is not authorized to access the requested entity.",
            Detail = specificException.Message,
        };
    }
}
