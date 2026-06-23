// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

using System.Linq.Expressions;
using AutoMapper;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using IdentityServer.Abstraction.Contracts;
using IdentityServer.Abstraction.DTO.Clients;
using IdentityServer.Abstraction.Entities;
using IdentityServer.Data.DuendeEntityExtensions;

namespace IdentityServer.Controllers;

[ApiController]
[Route("api/[controller]")]
[Produces("application/json")]
[Authorize(AuthenticationSchemes = Constants.AuthenticationSchemes.API_JWT_Bearer, Policy = Constants.Policies.M2MClientsRead)]
public class ClientsController : ControllerBase
{
    private readonly IStorage<ClientExt> _clientStorage;
    private readonly IMapper _mapper;

    public ClientsController(IStorage<ClientExt> clientStorage, IMapper mapper)
    {
        _clientStorage = clientStorage;
        _mapper = mapper;
    }

    [HttpPost("search")]
    [ProducesResponseType(typeof(SearchResult<ClientDtoSearchResponse>), StatusCodes.Status200OK)]
    [ProducesResponseType(StatusCodes.Status400BadRequest)]
    public async Task<ActionResult<SearchResult<ClientDtoSearchResponse>>> SearchClientsAsync([FromBody] ClientDtoSearchRequest item)
    {
        if (!ModelState.IsValid)
        {
            return BadRequest(ModelState);
        }

        Expression<Func<ClientExt, bool>> searchPredicate = x => x.ClientId.Contains(item.SearchTerm) || x.ClientName.Contains(item.SearchTerm);

        var totalCount = await _clientStorage.CountAsync(searchPredicate);

        var items = totalCount > 0
            ? _mapper.Map<List<ClientDtoSearchResponse>>(
                await _clientStorage.ToListAsync(
                    searchPredicate,
                    x => x.ClientId,
                    (item.Page - 1) * item.PageSize,
                    item.PageSize))
            : new List<ClientDtoSearchResponse>();

        var searchResult = new SearchResult<ClientDtoSearchResponse>
        {
            TotalCount = totalCount,
            Page = items,
            PageNumber = item.Page,
            PageSize = item.PageSize,
        };

        return Ok(searchResult);
    }

    [HttpGet("{clientId}")]
    [ProducesResponseType(typeof(ClientDtoSearchResponse), StatusCodes.Status200OK)]
    [ProducesResponseType(StatusCodes.Status404NotFound)]
    public async Task<ActionResult<ClientDtoSearchResponse>> GetClientByClientIdAsync(string clientId)
    {
        if (string.IsNullOrEmpty(clientId))
        {
            return BadRequest("Invalid client ID.");
        }

        var client = await _clientStorage.FirstOrDefaultAsync(x => x.ClientId == clientId);
        if (client == null)
        {
            return NotFound($"Client with ID '{clientId}' not found.");
        }

        var clientDto = _mapper.Map<ClientDtoSearchResponse>(client);
        return Ok(clientDto);
    }
}
