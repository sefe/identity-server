using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
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
public class SystemPermissionEnvironmentController : DataSourceControllerBase<SystemPermissionEnvironmentDtoRead>
{
    private readonly IDtoReadRepository<SystemPermissionDtoRead> _systemReadRepository;
    private readonly IDtoCreateRepository<SystemPermissionEnvironmentDtoRead, SystemPermissionEnvironmentDtoCreate> _envCreateRepository;
    private readonly IDtoReadRepository<SystemPermissionEnvironmentDtoRead> _envReadRepository;
    private readonly IDtoListRepository<SystemPermissionEnvironmentDtoRead, SystemPermissionEnvironment> _envListRepository;

    public SystemPermissionEnvironmentController(
        IDtoReadRepository<SystemPermissionDtoRead> systemReadRepository,
        IDtoCreateRepository<SystemPermissionEnvironmentDtoRead, SystemPermissionEnvironmentDtoCreate> envCreateRepository,
        IDtoReadRepository<SystemPermissionEnvironmentDtoRead> envReadRepository,
        IDtoListRepository<SystemPermissionEnvironmentDtoRead, SystemPermissionEnvironment> envListRepository,
        ILogger<SystemPermissionEnvironmentController> logger)
        : base(logger)
    {
        _systemReadRepository = systemReadRepository;
        _envCreateRepository = envCreateRepository;
        _envReadRepository = envReadRepository;
        _envListRepository = envListRepository;
    }

    [HttpGet("{id:int}")]
    public async Task<ActionResult<SystemPermissionEnvironmentDtoRead>> GetSystemPermissionEnvironmentByIdAsync(int id)
    {
        var item = await _envReadRepository.GetByIdAsync(User, id);
        return item == null
            ? NotFound()
            : Ok(item);
    }

    [HttpGet("{id:int}/contacts")]
    public async Task<ActionResult<string[]>> GetSystemPermissionEnvironmentContactsByIdAsync(int id)
    {
        // The contacts must be readable regardless of user access level to a system permission environment. Null is passed to avoid access exceptions.
        var item = await _envReadRepository.GetByIdAsync(null!, id);
        return item == null
            ? NotFound()
            : Ok(item.GetOwners());
    }

    /// <summary>
    /// Returns system permission environments the user has Writer permission to.
    /// </summary>
    /// <param name="request"
    ///        example="{&quot;skip&quot;:0,&quot;page&quot;:1,&quot;pageSize&quot;:5,&quot;sorts&quot;:[],&quot;filters&quot;:[],&quot;groups&quot;:[],&quot;aggregates&quot;:[],&quot;groupPaging&quot;:false}">Telerik DataSourceRequest</param>
    /// <returns>Page of system permission environments</returns>
    [HttpPost("datasource")]
    public async Task<ActionResult<DataEnvelope<SystemPermissionEnvironmentDtoRead>>> GetSystemPermissionEnvironmentsPagedAsync([FromBody] DataSourceRequest request)
    {
        var allMyWritableSystemPermissionEnvironmentsQuery = await _envListRepository.GetQueryableAsync(User);

        // query materialization required to enable processing of case-insensitive Contains in Telerik DataSource processing
        var materializedQuery = await allMyWritableSystemPermissionEnvironmentsQuery.ToListAsync();

        return await ProcessDatasourceRequest(request, materializedQuery.AsQueryable(), null, null);
    }

    [HttpPost]
    [Authorize(Policy = Constants.PolicyNames.RequireUserRole)]
    public async Task<ActionResult<SystemPermissionDtoRead>> CreateSystemPermissionEnvironmentAsync([FromBody] SystemPermissionEnvironmentDtoCreate item)
    {
        var addedResource = await _envCreateRepository.CreateAsync(User, item);
        // return full sys permission object for UI needs
        var updatedSystem = await _systemReadRepository.GetByIdAsync(User, addedResource.SystemPermissionId);
        return Ok(updatedSystem);
    }

    [HttpDelete("{id:int}")]
    [Authorize(Policy = Constants.PolicyNames.RequireUserRole)]
    public async Task<ActionResult<int>> DeleteSystemPermissionEnvironmentByIdAsync(int id)
    {
        int? deletedItem = await _envCreateRepository.DeleteAsync(User, id);

        return deletedItem == null
            ? NotFound()
            : Ok(deletedItem);
    }
}
