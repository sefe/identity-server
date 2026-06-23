// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using IdentityServer.Abstraction.Contracts;
using IdentityServer.Abstraction.DTO.History;

namespace IdentityServer.AdminPortal.Server.Controllers;

/// <summary>
/// Base controller for retrieving entity change history.
/// </summary>
[ApiController]
[Authorize]
[Produces("application/json")]
public abstract class HistoryControllerBase : ControllerBase
{
    private readonly IHistoryRepository _historyRepository;

    protected HistoryControllerBase(IHistoryRepository historyRepository)
    {
        _historyRepository = historyRepository;
    }

    /// <summary>
    /// Gets the complete change history for an entity and all its nested entities.
    /// </summary>
    /// <param name="entityId">The database ID of the entity.</param>
    /// <returns>A complete history response including all events.</returns>
    [HttpGet]
    [Route("{entityId:int}/history")]
    [ProducesResponseType(typeof(HistoryResponseDto), StatusCodes.Status200OK)]
    [ProducesResponseType(StatusCodes.Status404NotFound)]
    [ProducesResponseType(StatusCodes.Status403Forbidden)]
    public async Task<ActionResult<HistoryResponseDto>> GetHistory([FromRoute] int entityId)
    {
        var result = await _historyRepository.GetHistoryAsync(User, entityId);
        return Ok(result);
    }
}
