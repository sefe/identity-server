// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

using System.Security.Claims;
using IdentityServer.Abstraction.DTO.ApiResources;
using IdentityServer.AdminPortal.Server.Controllers;
using IdentityServer.AdminPortal.Test.Extensions;

namespace IdentityServer.AdminPortal.Test.Security;

public class ApiResourceSecurityDtoTest : ItemSecurityDtoTestBase<ApiResourceController, ApiResourceDtoRead, ApiResourceDtoCreate, ApiResourceShortDtoRead>
{
    protected override Func<int, ApiResourceDtoCreate> GetDefaultItem => ApiResourceControllerExtensions.GetDefaultApiResource;

    protected override Task<ApiResourceDtoRead> CreateFunc(ApiResourceController controller, ApiResourceDtoCreate item, ClaimsPrincipal user)
    {
        return controller.Call_CreateApiResourceAsync(item, user);
    }
    protected override Task<List<ApiResourceShortDtoRead>> GetAllFunc(ApiResourceController controller, ClaimsPrincipal user)
    {
        return controller.Call_GetApiResourcesPagedAsync(user);
    }
    protected override Task<ApiResourceDtoRead> GetFunc(ApiResourceController controller, int id, ClaimsPrincipal user)
    {
        return controller.Call_GetApiResourceAsync(id, user);
    }
    protected override Task<ApiResourceDtoRead> UpdateFunc(ApiResourceController controller, int id, ClaimsPrincipal user)
    {
        var item = new ApiResourceDtoUpdate
        {
            Id = id,
            Description = "Updated description",
        };
        return controller.Call_UpdateApiResourceAsync(item, user);
    }
    protected override Task<int?> DeleteFunc(ApiResourceController controller, int id, ClaimsPrincipal user)
    {
        return controller.Call_DeleteApiResourceAsync(id, user);
    }

    protected override Task<ApiResourceDtoRead> CloneFunc(ApiResourceController controller, int id, int targetEnvId, ClaimsPrincipal user)
    {
        var item = new ApiResourceDtoClone
        {
            Id = id,
            Name = Guid.NewGuid().ToString(),
            DisplayName = "Cloned ApiResource",
            SystemPermissionEnvironmentId = targetEnvId
        };
        return controller.Call_CloneApiResourceAsync(item, user);
    }
}
