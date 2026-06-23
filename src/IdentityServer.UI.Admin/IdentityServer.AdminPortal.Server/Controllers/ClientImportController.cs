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
public class ClientImportController : ControllerBase
{
    private readonly IDtoImportRepository<ClientRoleImportDto> _clientImportRepository;

    public ClientImportController(
        IDtoImportRepository<ClientRoleImportDto> ClientImportRepository)
    {
        _clientImportRepository = ClientImportRepository;
    }

    [HttpPut("{ClientId:int}/roles")]
    [Authorize(Policy = Constants.PolicyNames.RequireUserRole)]
    public async Task<ActionResult<OperationStatus>> ImportClientRoles(int ClientId, [FromBody] ClientRoleImportDto importDto)
    {
        var item = await _clientImportRepository.ImportAsync(User, ClientId, importDto);

        return Ok(item);
    }

    [HttpPost("{ClientId:int}/roles/validation")]
    [Authorize(Policy = Constants.PolicyNames.RequireUserRole)]
    public async Task<ActionResult<OperationStatus>> ValidateImportClientRoles(int ClientId, [FromBody] ClientRoleImportDto importDto)
    {
        var item = await _clientImportRepository.ValidateImportAsync(User, ClientId, importDto);

        return Ok(item);
    }
}
