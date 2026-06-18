using System.Linq.Expressions;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Telerik.DataSource;
using IdentityServer.Abstraction.Contracts;
using IdentityServer.Abstraction.DTO.ApiResources;
using IdentityServer.AdminPortal.Web.Models;
using IdentityServer.Data.DuendeEntityExtensions;

namespace IdentityServer.AdminPortal.Server.Controllers;

#pragma warning disable S6960 // Controllers should not have mixed responsibilities

[ApiController]
[Route("api/[controller]")]
[Authorize]
[Produces("application/json")]
public class ApiResourceController : AuditableDataSourceControllerBase<ApiResourceShortDtoRead>
{
    private readonly IDtoCreateRepository<ApiResourceDtoRead, ApiResourceDtoCreate> _apiResourceCreateRepository;
    private readonly IDtoCloneRepository<ApiResourceDtoRead, ApiResourceDtoClone> _apiResourceCloneRepository;
    private readonly IDtoUpdateRepository<ApiResourceDtoRead, ApiResourceDtoUpdate> _apiResourceUpdateRepository;
    private readonly IDtoReadRepository<ApiResourceDtoRead> _apiResourceReadRepository;
    private readonly IDtoListRepository<ApiResourceShortDtoRead, ApiResourceExt> _apiResourceListRepository;

    private readonly List<CustomFieldFilterDefinition> _customFieldFilters = new()
    {
        new CustomFieldFilterDefinition(nameof(ApiResourceShortDtoRead.SystemPermissionEnvironmentOwners), new Dictionary<FilterOperator, Func<string, Expression<Func<ApiResourceShortDtoRead, bool>>>>
        {
            { FilterOperator.Contains, value => x => x.SystemPermissionEnvironmentOwnersList.Any(owner => owner.Contains(value)) },
            { FilterOperator.DoesNotContain, value => x => x.SystemPermissionEnvironmentOwnersList.All(owner => !owner.Contains(value)) }
        })
    };

    public ApiResourceController(
        IDtoCreateRepository<ApiResourceDtoRead, ApiResourceDtoCreate> apiResourceCreateRepository,
        IDtoReadRepository<ApiResourceDtoRead> apiResourceReadRepository,
        IDtoListRepository<ApiResourceShortDtoRead, ApiResourceExt> apiResourceListRepository,
        IDtoUpdateRepository<ApiResourceDtoRead, ApiResourceDtoUpdate> apiResourceUpdateRepository,
        IDtoCloneRepository<ApiResourceDtoRead, ApiResourceDtoClone> apiResourceCloneRepository,
        IApiResourceAuditService auditService,
        ILogger<ApiResourceController> logger)
        : base(auditService, logger)
    {
        _apiResourceCreateRepository = apiResourceCreateRepository;
        _apiResourceReadRepository = apiResourceReadRepository;
        _apiResourceListRepository = apiResourceListRepository;
        _apiResourceUpdateRepository = apiResourceUpdateRepository;
        _apiResourceCloneRepository = apiResourceCloneRepository;
    }

    [HttpGet("{id:int}")]
    public async Task<ActionResult<ApiResourceDtoRead>> GetApiResourceByIdAsync(int id)
    {
        var item = await _apiResourceReadRepository.GetByIdAsync(User, id);
        return item == null
            ? NotFound()
            : Ok(item);
    }

    /// <summary>
    /// Process Telerik DataGridRequest.
    /// </summary>
    /// <param name="gridRequest"
    ///        example="{&quot;skip&quot;:0,&quot;page&quot;:1,&quot;pageSize&quot;:5,&quot;sorts&quot;:[],&quot;filters&quot;:[],&quot;groups&quot;:[],&quot;aggregates&quot;:[],&quot;groupPaging&quot;:false}">Telerik DataSourceRequest</param>
    /// <returns>Filtered/Sorted/Grouped data</returns>
    [HttpPost("datasource")]
    public async Task<ActionResult<DataEnvelope<ApiResourceShortDtoRead>>> GetApiResourcesPagedAsync([FromBody] DataSourceRequest gridRequest)
    {
        var apiResourcesQuery = await _apiResourceListRepository.GetQueryableAsync(User);

        return await ProcessDatasourceRequest(gridRequest, apiResourcesQuery, _customFieldFilters, null);
    }

    [HttpPost]
    [Authorize(Policy = Constants.PolicyNames.RequireUserRole)]
    public async Task<ActionResult<ApiResourceDtoRead>> CreateApiResourceAsync([FromBody] ApiResourceDtoCreate item)
    {
        var addedResource = await _apiResourceCreateRepository.CreateAsync(User, item);
        return Ok(addedResource);
    }

    [HttpPost("clone")]
    [Authorize(Policy = Constants.PolicyNames.RequireUserRole)]
    public async Task<ActionResult<ApiResourceDtoRead>> CloneApiResourceAsync([FromBody] ApiResourceDtoClone item)
    {
        var addedResource = await _apiResourceCloneRepository.CloneAsync(User, item);
        return Ok(addedResource);
    }

    [HttpDelete("{id:int}")]
    [Authorize(Policy = Constants.PolicyNames.RequireUserRole)]
    public async Task<ActionResult<int>> DeleteApiResourceByIdAsync(int id)
    {
        int? deletedItem = await _apiResourceCreateRepository.DeleteAsync(User, id);

        return deletedItem == null
            ? NotFound()
            : Ok(deletedItem);
    }

    [HttpPut]
    [Authorize(Policy = Constants.PolicyNames.RequireUserRole)]
    public async Task<ActionResult<ApiResourceDtoRead>> UpdateApiResourceAsync([FromBody] ApiResourceDtoUpdate item)
    {
        var addedResource = await _apiResourceUpdateRepository.UpdateAsync(User, item);
        return Ok(addedResource);
    }
}

#pragma warning restore S6960 // Controllers should not have mixed responsibilities
