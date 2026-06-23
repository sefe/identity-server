// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using IdentityServer.Abstraction.Contracts;
using IdentityServer.Abstraction.DTO.ApiResources;

namespace IdentityServer.AdminPortal.Server.Controllers;

[Route("api/apiresource/scope")]
public class ApiResourcePropertyScopeController
    : BasePropertyController<ApiResourcePropertyScopeDtoRead, ApiResourcePropertyScopeDtoCreate>
{
    private readonly IDtoUpdateRepository<ApiResourcePropertyScopeDtoRead, ApiResourcePropertyScopeDtoUpdate> _apiResourceScopeUpdateRepository;

    public ApiResourcePropertyScopeController(
        IDtoCreateRepository<ApiResourcePropertyScopeDtoRead, ApiResourcePropertyScopeDtoCreate> apiResourceScopeCreateRepository,
        IDtoUpdateRepository<ApiResourcePropertyScopeDtoRead, ApiResourcePropertyScopeDtoUpdate> apiResourceScopeUpdateRepository)
        : base(apiResourceScopeCreateRepository)
    {
        _apiResourceScopeUpdateRepository = apiResourceScopeUpdateRepository;
    }

    [HttpPut]
    [Authorize(Policy = Constants.PolicyNames.RequireUserRole)]
    public async Task<ActionResult<ApiResourcePropertyScopeDtoRead>> UpdateApiResourceScopeAsync([FromBody] ApiResourcePropertyScopeDtoUpdate item)
    {
        var addedResource = await _apiResourceScopeUpdateRepository.UpdateAsync(User, item);
        return Ok(addedResource);
    }
}
