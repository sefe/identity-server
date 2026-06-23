// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using IdentityServer.Abstraction.Contracts.MicrosoftGraph;
using IdentityServer.Abstraction.Entities.EntraEntities;
using IdentityServer.AdminPortal.Web.Services.Search;

namespace IdentityServer.AdminPortal.Server.Controllers;

[ApiController]
[Route("api/[controller]")]
[Authorize]
[Produces("application/json")]
public class GroupController : ControllerBase
{
    private readonly IEntraGroupService _entraGroupService;

    public GroupController(IEntraGroupService entraGroupService)
    {
        _entraGroupService = entraGroupService;
    }

    [HttpGet("search/displayName/{searchString}")]
    public async Task<ActionResult<GroupResponse>> GetGroupsByDisplayName(string searchString, [FromQuery] string? skipToken)
    {
        searchString = searchString.Trim();
        if (searchString.Length < SearchFormModel.MinSearchSymbols)
        {
            return BadRequest(SearchFormModel.MinSearchSymbolsErrorMessage);
        }
        var groups = await _entraGroupService.GetGroupsByDisplayNameAsync(searchString, skipToken);
        return Ok(groups);
    }
}
