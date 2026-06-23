// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

using Microsoft.AspNetCore.Diagnostics;
using Microsoft.AspNetCore.Mvc;

namespace IdentityServer.AdminPortal.Server.Controllers;

/// <summary>
/// https://learn.microsoft.com/en-us/aspnet/core/web-api/handle-errors?view=aspnetcore-8.0
/// </summary>
[ApiExplorerSettings(IgnoreApi = true)]
[Produces("application/json")]
[ApiController]
[Route("/")]
public class ErrorController : ControllerBase
{
    [Route("error-development")]
    public IActionResult HandleErrorDevelopment(
        [FromServices] IHostEnvironment hostEnvironment)
    {
        if (!hostEnvironment.IsDevelopment())
        {
            return NotFound();
        }

        var exceptionHandlerFeature =
            HttpContext.Features.Get<IExceptionHandlerFeature>()!;

        return Problem(title: exceptionHandlerFeature.Error.Message);
    }

    [Route("error")]
    public IActionResult HandleError() =>
        Problem();
}
