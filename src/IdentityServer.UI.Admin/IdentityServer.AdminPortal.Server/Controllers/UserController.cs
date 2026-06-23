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
public class UserController : ControllerBase
{
    private readonly IEntraUserService _entraService;

    public UserController(IEntraUserService entraService)
    {
        _entraService = entraService;
    }

    [HttpGet]
    [Route("{id}")]
    public async Task<ActionResult<UserResponse>> GetUserById(string id)
    {
        var user = await _entraService.GetUserByObjectIdAsync(id);
        return Ok(user);
    }

    [HttpGet]
    [Route("search/displayName/{searchString}")]
    public async Task<ActionResult<UserResponse>> SearchUsersByDisplayName(string searchString)
    {
        searchString = searchString.Trim();
        if (searchString.Length < SearchFormModel.MinSearchSymbols)
        {
            return BadRequest(SearchFormModel.MinSearchSymbolsErrorMessage);
        }
        var users = await _entraService.GetUsersByDisplayNameAsync(searchString);
        return Ok(users);
    }
}
