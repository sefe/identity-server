// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

using System.Security.Claims;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using NSubstitute;

namespace IdentityServer.Test.Controller;

public abstract class ControllerTestBase
{
    public static void SetControllerContext(ControllerBase controller, ClaimsPrincipal claimsPrincipal)
    {
        var httpContext = Substitute.For<HttpContext>();
        httpContext.User.Returns(claimsPrincipal);

        controller.ControllerContext = new ControllerContext
        {
            HttpContext = httpContext
        };
    }
}
