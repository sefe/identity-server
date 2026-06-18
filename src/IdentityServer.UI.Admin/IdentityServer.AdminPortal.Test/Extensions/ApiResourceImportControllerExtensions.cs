using System.Security.Claims;
using Microsoft.AspNetCore.Mvc;
using IdentityServer.Abstraction.DTO.Import;
using IdentityServer.AdminPortal.Server.Controllers;
using IdentityServer.AdminPortal.Test.Controller;

namespace IdentityServer.AdminPortal.Test.Extensions;

public static class ApiResourceImportControllerExtensions
{
    public static ApiResourceRoleImportDto NewImportDto()
    {
        return new ApiResourceRoleImportDto
        {
            // Fill with sensible defaults for tests
            ImportStrategy = ImportStrategy.Replace,
            Roles = new List<Abstraction.DTO.Export.RoleValueObject<Abstraction.DTO.Export.ApiResourceRoleMappingValueObject>>()
        };
    }

    public static async Task<OperationStatus> Call_ImportApiResourceRolesAsync(
        this ApiResourceImportController controller,
        int apiResourceId,
        ApiResourceRoleImportDto importDto,
        ClaimsPrincipal user)
    {
        ControllerTestBase.SetControllerContext(controller, user);
        var result = await controller.ImportApiResourceRoles(apiResourceId, importDto);
        var entity = ((OkObjectResult)result.Result).Value as OperationStatus;
        return entity!;
    }

    public static async Task<OperationStatus> Call_ValidateImportApiResourceRolesAsync(
        this ApiResourceImportController controller,
        int apiResourceId,
        ApiResourceRoleImportDto importDto,
        ClaimsPrincipal user)
    {
        ControllerTestBase.SetControllerContext(controller, user);
        var result = await controller.ValidateImportApiResourceRoles(apiResourceId, importDto);
        var entity = ((OkObjectResult)result.Result).Value as OperationStatus;
        return entity!;
    }
}
