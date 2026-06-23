// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

using Microsoft.AspNetCore.Mvc;
using IdentityServer.Abstraction.Entities;

namespace IdentityServer.Controllers;

[ApiController]
[Route("api/[controller]")]
[Produces("application/json")]
public class HealthController : ControllerBase
{

    [HttpGet]
    public ActionResult<HealthStatus> GetHealth()
    {
        return Ok(new HealthStatus(HealthStatus.Healthy));
    }
}
