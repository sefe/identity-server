using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using IdentityServer.Abstraction.Contracts;
using IdentityServer.Abstraction.DTO.SystemPermissions;

namespace IdentityServer.AdminPortal.Server.Controllers;

#pragma warning disable S6960 // Controllers should not have mixed responsibilities

[ApiController]
[Route("api/[controller]")]
[Authorize]
[Produces("application/json")]
public class SystemPermissionRoleController : ControllerBase
{
    private readonly IDtoCreateRepository<SystemPermissionRoleDtoRead, SystemPermissionRoleDtoCreate> _roleCreateRepository;
    private readonly IDtoUpdateRepository<SystemPermissionRoleDtoRead, SystemPermissionRoleDtoUpdate> _roleUpdateRepository;

    public SystemPermissionRoleController(
        IDtoCreateRepository<SystemPermissionRoleDtoRead, SystemPermissionRoleDtoCreate> roleCreateRepository,
        IDtoUpdateRepository<SystemPermissionRoleDtoRead, SystemPermissionRoleDtoUpdate> roleUpdateRepository
        )
    {
        _roleCreateRepository = roleCreateRepository;
        _roleUpdateRepository = roleUpdateRepository;
    }

    [HttpPost]
    [Authorize(Policy = Constants.PolicyNames.RequireUserRole)]
    public async Task<ActionResult<SystemPermissionRoleDtoRead>> CreateSystemPermissionRoleAsync([FromBody] SystemPermissionRoleDtoCreate item)
    {
        var addedResource = await _roleCreateRepository.CreateAsync(User, item);
        return Ok(addedResource);
    }

    [HttpPut]
    [Authorize(Policy = Constants.PolicyNames.RequireUserRole)]
    public async Task<ActionResult<SystemPermissionRoleDtoRead>> UpdateSystemPermissionRoleAsync([FromBody] SystemPermissionRoleDtoUpdate item)
    {
        var updatedResource = await _roleUpdateRepository.UpdateAsync(User, item);
        return Ok(updatedResource);
    }

    [HttpDelete("{id:int}")]
    [Authorize(Policy = Constants.PolicyNames.RequireUserRole)]
    public async Task<ActionResult<int>> DeleteSystemPermissionRoleByIdAsync(int id)
    {
        int? deletedItem = await _roleCreateRepository.DeleteAsync(User, id);

        return deletedItem == null
            ? NotFound()
            : Ok(deletedItem);
    }
}

#pragma warning restore S6960 // Controllers should not have mixed responsibilities
