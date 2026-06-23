// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

using System.Linq.Expressions;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Telerik.DataSource;
using IdentityServer.Abstraction.Contracts;
using IdentityServer.Abstraction.DTO.Clients;
using IdentityServer.AdminPortal.Web.Models;
using IdentityServer.Data.DuendeEntityExtensions;

namespace IdentityServer.AdminPortal.Server.Controllers;

#pragma warning disable S6960 // Controllers should not have mixed responsibilities

[ApiController]
[Route("api/[controller]")]
[Authorize]
[Produces("application/json")]
public class ClientController : AuditableDataSourceControllerBase<ClientShortDtoRead>
{
    private readonly IDtoCreateRepository<ClientDtoRead, ClientDtoCreate> _clientCreateRepository;
    private readonly IDtoCloneRepository<ClientDtoRead, ClientDtoClone> _clientCloneRepository;
    private readonly IDtoUpdateRepository<ClientDtoRead, ClientDtoUpdate> _clientUpdateRepository;
    private readonly IDtoReadRepository<ClientDtoRead> _clientReadRepository;
    private readonly IDtoListRepository<ClientShortDtoRead, ClientExt> _clientListRepository;

    private readonly List<CustomFieldFilterDefinition> _customFieldFilters = new()
    {
        new CustomFieldFilterDefinition(nameof(ClientShortDtoRead.SystemPermissionEnvironmentOwners), new Dictionary<FilterOperator, Func<string, Expression<Func<ClientShortDtoRead, bool>>>>
        {
            { FilterOperator.Contains, value => x => x.SystemPermissionEnvironmentOwnersList.Any(owner => owner.Contains(value)) },
            { FilterOperator.DoesNotContain, value => x => x.SystemPermissionEnvironmentOwnersList.All(owner => !owner.Contains(value)) }
        })
    };

    public ClientController(
        IDtoCreateRepository<ClientDtoRead, ClientDtoCreate> clientCreateRepository,
        IDtoReadRepository<ClientDtoRead> clientReadRepository,
        IDtoListRepository<ClientShortDtoRead, ClientExt> clientListRepository,
        IDtoUpdateRepository<ClientDtoRead, ClientDtoUpdate> clientUpdateRepository,
        IDtoCloneRepository<ClientDtoRead, ClientDtoClone> clientCloneRepository,
        IClientAuditService auditService,
        ILogger<ClientController> logger)
        : base(auditService, logger)
    {
        _clientCreateRepository = clientCreateRepository;
        _clientReadRepository = clientReadRepository;
        _clientListRepository = clientListRepository;
        _clientUpdateRepository = clientUpdateRepository;
        _clientCloneRepository = clientCloneRepository;
    }

    /// <summary>
    /// Process Telerik DataGridRequest.
    /// </summary>
    /// <param name="gridRequest"
    ///        example="{&quot;skip&quot;:0,&quot;page&quot;:1,&quot;pageSize&quot;:5,&quot;sorts&quot;:[],&quot;filters&quot;:[],&quot;groups&quot;:[],&quot;aggregates&quot;:[],&quot;groupPaging&quot;:false}">Telerik DataSourceRequest</param>
    /// <returns>Filtered/Sorted/Grouped data</returns>
    [HttpPost("datasource")]
    public async Task<ActionResult<DataEnvelope<ClientShortDtoRead>>> GetClientsPagedAsync([FromBody] DataSourceRequest gridRequest)
    {
        var clientsQuery = await _clientListRepository.GetQueryableAsync(User);

        return await ProcessDatasourceRequest(gridRequest, clientsQuery, _customFieldFilters, null);
    }

    /// <summary>
    /// Process Telerik DataGridRequest for clients filtered by scope name.
    /// </summary>
    /// <param name="scopeName">The scope name to filter clients by</param>
    /// <param name="gridRequest"
    ///        example="{&quot;skip&quot;:0,&quot;page&quot;:1,&quot;pageSize&quot;:5,&quot;sorts&quot;:[],&quot;filters&quot;:[],&quot;groups&quot;:[],&quot;aggregates&quot;:[],&quot;groupPaging&quot;:false}">Telerik DataSourceRequest</param>
    /// <returns>Filtered/Sorted/Grouped data</returns>
    [HttpPost("datasource/scope/{scopeName}")]
    public async Task<ActionResult<DataEnvelope<ClientShortDtoRead>>> GetClientsByScopePagedAsync(string scopeName, [FromBody] DataSourceRequest gridRequest)
    {
        Expression<Func<ClientExt, bool>> filter = x => x.AllowedScopes.Any(s => s.Scope == scopeName);

        var clientsQuery = await _clientListRepository.GetQueryableAsync(User, filter);

        return await ProcessDatasourceRequest(gridRequest, clientsQuery, null, null);
    }

    [HttpGet("{id:int}")]
    public async Task<ActionResult<ClientDtoRead>> GetClientByIdAsync(int id)
    {
        var item = await _clientReadRepository.GetByIdAsync(User, id);
        return item == null
            ? NotFound()
            : Ok(item);
    }

    [HttpPost]
    [Authorize(Policy = Constants.PolicyNames.RequireUserRole)]
    public async Task<ActionResult<ClientDtoRead>> CreateClientAsync([FromBody] ClientDtoCreate item)
    {
        var addedResource = await _clientCreateRepository.CreateAsync(User, item);
        return Ok(addedResource);
    }

    [HttpPost("clone")]
    [Authorize(Policy = Constants.PolicyNames.RequireUserRole)]
    public async Task<ActionResult<ClientDtoRead>> CloneClientAsync([FromBody] ClientDtoClone item)
    {
        var addedResource = await _clientCloneRepository.CloneAsync(User, item);
        return Ok(addedResource);
    }

    [HttpDelete("{id:int}")]
    [Authorize(Policy = Constants.PolicyNames.RequireUserRole)]
    public async Task<ActionResult<int>> DeleteClientByIdAsync(int id)
    {
        int? deletedItem = await _clientCreateRepository.DeleteAsync(User, id);

        return deletedItem == null
            ? NotFound()
            : Ok(deletedItem);
    }

    [HttpPut]
    [Authorize(Policy = Constants.PolicyNames.RequireUserRole)]
    public async Task<ActionResult<ClientDtoRead>> UpdateClientAsync([FromBody] ClientDtoUpdate item)
    {
        var addedResource = await _clientUpdateRepository.UpdateAsync(User, item);
        return Ok(addedResource);
    }
}

#pragma warning restore S6960 // Controllers should not have mixed responsibilities
