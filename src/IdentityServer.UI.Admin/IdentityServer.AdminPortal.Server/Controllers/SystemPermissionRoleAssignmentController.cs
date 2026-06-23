// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Telerik.DataSource;
using IdentityServer.Abstraction.Configs;
using IdentityServer.Abstraction.Contracts;
using IdentityServer.Abstraction.Contracts.MicrosoftGraph;
using IdentityServer.Abstraction.DTO.SystemPermissions;
using IdentityServer.Abstraction.Entities.EntraEntities;
using IdentityServer.Abstraction.Entities.IdentityServerConfig.SystemPermissions;
using IdentityServer.AdminPortal.Web.Models;

namespace IdentityServer.AdminPortal.Server.Controllers;

[ApiController]
[Route("api/[controller]")]
[Authorize]
[Produces("application/json")]
public class SystemPermissionRoleAssignmentController : DataSourceControllerBase<User>
{
    private readonly IAuthConfig _authConfig;
    private readonly IEntraGroupService _entraGroupService;
    private readonly IDtoParentListRepository<SystemPermissionRoleDtoRead> _roleParentRepo;

    public SystemPermissionRoleAssignmentController(
        IAuthConfig authConfig,
        IEntraGroupService userCacheService,
        IDtoParentListRepository<SystemPermissionRoleDtoRead> roleParentRepo,
        ILogger<SystemPermissionRoleAssignmentController> logger)
        : base(logger)
    {
        _authConfig = authConfig;
        _entraGroupService = userCacheService;
        _roleParentRepo = roleParentRepo;
    }

    /// <summary>
    /// Returns eligible user assignments for the provided system permission environment and role.
    /// </summary>
    /// <param name="gridRequest"
    ///        example="{&quot;skip&quot;:0,&quot;page&quot;:1,&quot;pageSize&quot;:5,&quot;sorts&quot;:[],&quot;filters&quot;:[],&quot;groups&quot;:[],&quot;aggregates&quot;:[],&quot;groupPaging&quot;:false}">Telerik DataSourceRequest</param>
    /// <param name="systemPermissionEnvironmentId">System Permission Environment for assignment.</param>
    /// <param name="roleType">Planned assignment role</param>
    /// <returns>Page of eligible assignments.</returns>
    [HttpPost("datasource")]
    public async Task<ActionResult<DataEnvelope<User>>> GetEligibleUserAssignmentsPagedAsync(
        [FromBody] DataSourceRequest gridRequest,
        [FromQuery(Name = "envId")] int systemPermissionEnvironmentId,
        [FromQuery] SystemPermissionRoleType roleType
    )
    {
        // get all existing permissions for the env ID
        var existingRoleAssignments = await _roleParentRepo.GetAllByParentIdAsync(User, systemPermissionEnvironmentId);
        // for a new Reader assignment filter out existing Readers and Writers. For a new Writer - existing Writers only.
        var alreadyAssignedOids = existingRoleAssignments.Where(p => p.RoleType >= roleType).Select(p => p.OId);
        // get all potential assignments
        var groupId = roleType switch
        {
            SystemPermissionRoleType.Reader => _authConfig.ReaderGroupId,
            SystemPermissionRoleType.Writer => _authConfig.ContributorGroupId,
            _ => throw new ArgumentException($"Unsupported Role Type '{roleType}'", nameof(roleType))
        };
        var eligibleUsers = await _entraGroupService.GetGroupMembersAsync(groupId);
        // filter out existing assignments
        eligibleUsers = eligibleUsers.Where(c => !alreadyAssignedOids.Contains(c.OId)).OrderBy(c => c.DisplayName).ToList();

        return await ProcessDatasourceRequest(gridRequest, eligibleUsers.AsQueryable(), null, null);
    }
}
