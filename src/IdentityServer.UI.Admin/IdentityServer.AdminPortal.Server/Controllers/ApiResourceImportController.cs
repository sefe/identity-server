// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using IdentityServer.Abstraction.Contracts;
using IdentityServer.Abstraction.DTO.Import;

namespace IdentityServer.AdminPortal.Server.Controllers;

[ApiController]
[Route("api/[controller]")]
[Authorize]
[Produces("application/json")]
public class ApiResourceImportController : ControllerBase
{
    private readonly IDtoImportRepository<ApiResourceRoleImportDto> _apiResourceImportRepository;

    public ApiResourceImportController(
        IDtoImportRepository<ApiResourceRoleImportDto> apiResourceImportRepository)
    {
        _apiResourceImportRepository = apiResourceImportRepository;
    }

    [HttpPut("{apiResourceId:int}/roles")]
    [Authorize(Policy = Constants.PolicyNames.RequireUserRole)]
    public async Task<ActionResult<OperationStatus>> ImportApiResourceRoles(int apiResourceId, [FromBody] ApiResourceRoleImportDto importDto)
    {
        var item = await _apiResourceImportRepository.ImportAsync(User, apiResourceId, importDto);

        return Ok(item);
    }

    [HttpPost("{apiResourceId:int}/roles/validation")]
    [Authorize(Policy = Constants.PolicyNames.RequireUserRole)]
    public async Task<ActionResult<OperationStatus>> ValidateImportApiResourceRoles(int apiResourceId, [FromBody] ApiResourceRoleImportDto importDto)
    {
        var item = await _apiResourceImportRepository.ValidateImportAsync(User, apiResourceId, importDto);

        return Ok(item);
    }
}
