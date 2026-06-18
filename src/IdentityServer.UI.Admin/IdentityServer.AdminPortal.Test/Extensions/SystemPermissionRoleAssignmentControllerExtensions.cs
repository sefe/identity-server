using System.Security.Claims;
using Microsoft.AspNetCore.Mvc;
using Telerik.DataSource;
using IdentityServer.Abstraction.Entities.EntraEntities;
using IdentityServer.Abstraction.Entities.IdentityServerConfig.SystemPermissions;
using IdentityServer.AdminPortal.Server.Controllers;
using IdentityServer.AdminPortal.Test.Controller;
using IdentityServer.AdminPortal.Web.Models;

namespace IdentityServer.AdminPortal.Test.Extensions;

public static class SystemPermissionRoleAssignmentControllerExtensions
{
    public static async Task<DataEnvelope<User>> Call_GetEligibleUserAssignmentsPagedAsync(
        this SystemPermissionRoleAssignmentController controller,
        DataSourceRequest gridRequest,
        int systemPermissionEnvironmentId,
        SystemPermissionRoleType roleType,
        ClaimsPrincipal user)
    {
        ControllerTestBase.SetControllerContext(controller, user);
        var result = await controller.GetEligibleUserAssignmentsPagedAsync(gridRequest, systemPermissionEnvironmentId, roleType);
        var okResult = result.Result as OkObjectResult;
        return okResult?.Value as DataEnvelope<User>;
    }
}
