// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

using System.Linq.Expressions;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Telerik.DataSource;
using IdentityServer.Abstraction.Contracts;
using IdentityServer.Abstraction.DTO.SystemPermissions;
using IdentityServer.Abstraction.Entities.IdentityServerConfig.SystemPermissions;
using IdentityServer.AdminPortal.Web.Models;

namespace IdentityServer.AdminPortal.Server.Controllers;

[ApiController]
[Route("api/[controller]")]
[Authorize]
[Produces("application/json")]
public class SystemPermissionController : AuditableDataSourceControllerBase<SystemPermissionShortDtoRead>
{
    private readonly IDtoCreateRepository<SystemPermissionDtoRead, SystemPermissionDtoCreate> _systemCreateRepository;
    private readonly IDtoReadRepository<SystemPermissionDtoRead> _systemReadRepository;
    private readonly IDtoListRepository<SystemPermissionShortDtoRead, SystemPermission> _systemListRepository;
    private readonly IDtoUpdateRepository<SystemPermissionDtoRead, SystemPermissionDtoUpdate> _systemUpdateRepository;

    private readonly List<CustomFieldFilterDefinition> _customFieldFilters = new()
    {
        new CustomFieldFilterDefinition(nameof(SystemPermissionShortDtoRead.Owners), new Dictionary<FilterOperator, Func<string, Expression<Func<SystemPermissionShortDtoRead, bool>>>>
        {
            { FilterOperator.Contains, value => x => x.OwnersList.Any(owner => owner.Contains(value)) },
            { FilterOperator.DoesNotContain, value => x => x.OwnersList.All(owner => !owner.Contains(value)) }
        }),
        new CustomFieldFilterDefinition(nameof(SystemPermissionShortDtoRead.EnvironmentNames), new Dictionary<FilterOperator, Func<string, Expression<Func<SystemPermissionShortDtoRead, bool>>>>
        {
            { FilterOperator.Contains, value => x => x.EnvironmentNamesList.Any(name => name.Contains(value)) },
            { FilterOperator.DoesNotContain, value => x => x.EnvironmentNamesList.All(name => !name.Contains(value)) }
        })
    };

    public SystemPermissionController(
        IDtoCreateRepository<SystemPermissionDtoRead, SystemPermissionDtoCreate> systemCreateRepository,
        IDtoReadRepository<SystemPermissionDtoRead> systemReadRepository,
        IDtoListRepository<SystemPermissionShortDtoRead, SystemPermission> systemListRepository,
        IDtoUpdateRepository<SystemPermissionDtoRead, SystemPermissionDtoUpdate> systemUpdateRepository,
        ISystemPermissionAuditService auditService,
        ILogger<SystemPermissionController> logger)
        : base(auditService, logger)
    {
        _systemCreateRepository = systemCreateRepository;
        _systemReadRepository = systemReadRepository;
        _systemListRepository = systemListRepository;
        _systemUpdateRepository = systemUpdateRepository;
    }

    [HttpGet("{id:int}")]
    public async Task<ActionResult<SystemPermissionDtoRead>> GetSystemPermissionByIdAsync(int id)
    {
        var item = await _systemReadRepository.GetByIdAsync(User, id);
        return item == null
            ? NotFound()
            : Ok(item);
    }

    /// <summary>
    /// Process Telerik DataGridRequest.
    /// </summary>
    /// <param name="request"
    ///        example="{&quot;skip&quot;:0,&quot;page&quot;:1,&quot;pageSize&quot;:5,&quot;sorts&quot;:[],&quot;filters&quot;:[],&quot;groups&quot;:[],&quot;aggregates&quot;:[],&quot;groupPaging&quot;:false}">Telerik DataSourceRequest</param>
    /// <returns>Filtered/Sorted/Grouped data</returns>
    [HttpPost("datasource")]
    public async Task<ActionResult<DataEnvelope<SystemPermissionShortDtoRead>>> GetSystemPermissionsPagedAsync([FromBody] DataSourceRequest request)
    {
        var systemPermissionsQuery = await _systemListRepository.GetQueryableAsync(User);

        return await ProcessDatasourceRequest(request, systemPermissionsQuery, _customFieldFilters, _systemListRepository.PostProcess);
    }

    [HttpPost]
    [Authorize(Policy = Constants.PolicyNames.RequireUserRole)]
    public async Task<ActionResult<SystemPermissionDtoRead>> CreateSystemPermissionAsync([FromBody] SystemPermissionDtoCreate item)
    {
        var addedResource = await _systemCreateRepository.CreateAsync(User, item);
        return Ok(addedResource);
    }

    [HttpPut]
    [Authorize(Policy = Constants.PolicyNames.RequireUserRole)]
    public async Task<ActionResult<SystemPermissionDtoRead>> UpdateSystemPermissionAsync([FromBody] SystemPermissionDtoUpdate item)
    {
        var updatedResources = await _systemUpdateRepository.UpdateAsync(User, item);
        return Ok(updatedResources);
    }

    [HttpDelete("{id:int}")]
    [Authorize(Policy = Constants.PolicyNames.RequireUserRole)]
    public async Task<ActionResult<int>> DeleteSystemPermissionByIdAsync(int id)
    {
        int? deletedItem = await _systemCreateRepository.DeleteAsync(User, id);

        return deletedItem == null
            ? NotFound()
            : Ok(deletedItem);
    }
}
