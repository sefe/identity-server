// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using IdentityServer.Abstraction.DTO.ApiResources;
using IdentityServer.Data.Services;

namespace IdentityServer.Controllers;

[ApiController]
[Route("api/[controller]")]
[Produces("application/json")]
[Authorize(AuthenticationSchemes = Constants.AuthenticationSchemes.API_JWT_Bearer, Policy = Constants.Policies.M2MReportsRead)]
public class ReportsController : ControllerBase
{
    private readonly IReportingService _reportingService;

    public ReportsController(IReportingService reportingService)
    {
        _reportingService = reportingService;
    }

    [HttpPost("apiroles")]
    [ProducesResponseType(typeof(ApiRolesAssignmentsDto), StatusCodes.Status200OK)]
    [ProducesResponseType(StatusCodes.Status400BadRequest)]
    public async Task<ActionResult<ApiRolesAssignmentsDto>> ReportApiRolesAsync([FromBody] ApiRolesReportRequest request)
    {
        if (!ModelState.IsValid)
        {
            return BadRequest(ModelState);
        }

        var report = await _reportingService.BuildReportAsync(request);
        return Ok(report);
    }
}

