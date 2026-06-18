using Microsoft.AspNetCore.Mvc;
using IdentityServer.Abstraction.Exceptions;
using IdentityServer.Core.Infrastructure;

namespace IdentityServer.AdminPortal.Server.ExceptionHandlers;

public class UserClaimExceptionHandler : BasicExceptionHandler<UserClaimException>
{
    public UserClaimExceptionHandler(IProblemDetailsService problemDetailsService, ILogger<UserClaimExceptionHandler> logger)
        : base(problemDetailsService, logger)
    {
    }

    protected override ProblemDetails CreateProblemDetails(HttpContext httpContext, UserClaimException specificException)
    {
        return new ProblemDetails
        {
            Status = StatusCodes.Status400BadRequest,
            Detail = specificException.Message,
            Title = "The logged in user lacks mandatory profile information. A re-login may fix this issue.",
        };
    }
}
