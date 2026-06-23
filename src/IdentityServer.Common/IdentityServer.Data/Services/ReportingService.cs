// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

using IdentityServer.Abstraction.Contracts;
using IdentityServer.Abstraction.DTO.ApiResources;
using IdentityServer.Abstraction.Entities.IdentityServerConfig;
using IdentityServer.Abstraction.Exceptions;
using IdentityServer.Data.DuendeEntityExtensions;

namespace IdentityServer.Data.Services;

public class ReportingService : IReportingService
{
    private readonly IStorage<ApiResourceExt> _apiStorage;

    public ReportingService(IStorage<ApiResourceExt> apiStorage)
    {
        _apiStorage = apiStorage;
    }

    public async Task<ApiRolesAssignmentsDto> BuildReportAsync(ApiRolesReportRequest request)
    {
        request.ApiResourceName = request.ApiResourceName.Trim().ToLowerInvariant();
        var api = await _apiStorage.FirstOrDefaultAsync(x => x.Name == request.ApiResourceName)
            ?? throw new EntityReferenceException($"API resource with name '{request.ApiResourceName}' not found.");

        var roles = api.Roles;

        if (!string.IsNullOrEmpty(request.Role))
        {
            roles = roles.Where(_ => _.RoleName == request.Role).ToList();
            if (roles.Count == 0)
            {
                throw new EntityReferenceException($"No roles found for API resource with name '{request.ApiResourceName}' and role '{request.Role}'.");
            }
        }

        var response = new ApiRolesAssignmentsDto()
        {
            ApiResourceName = api.Name,
            Assignments = new()
        };

        var mapType = request.RoleMapType == default ? (RoleMapType?)null : (RoleMapType)Enum.Parse(typeof(RoleMapType), request.RoleMapType);

        response.Assignments = roles.ToDictionary(_ => _.RoleName,
            _ => _.Mappings?
                .Where(rm => !mapType.HasValue || rm.MappingType == mapType.Value)
                .Select(rm => new ApiRolesPrincipalDto() { Type = rm.MappingType, Id = rm.Value, Name = rm.Description })
                .ToList() ?? []);

        return response;
    }
}
