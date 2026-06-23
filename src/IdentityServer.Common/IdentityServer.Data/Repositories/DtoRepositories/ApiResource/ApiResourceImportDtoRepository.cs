// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

using System.Security.Claims;
using Microsoft.Extensions.Logging;
using IdentityServer.Abstraction.Contracts;
using IdentityServer.Abstraction.DTO.Export;
using IdentityServer.Abstraction.DTO.Import;
using IdentityServer.Abstraction.Entities.IdentityServerConfig;
using IdentityServer.Abstraction.Exceptions;
using IdentityServer.Data.DuendeEntityExtensions;
using IdentityServer.Data.Entities.Roles;
using IdentityServer.Data.Services;

namespace IdentityServer.Data.Repositories.DtoRepositories.ApiResource;

/// <summary>
/// Responsible for bulk changes for <seealso cref="ApiResourceExt"/> entities.
/// </summary>
internal class ApiResourceImportDtoRepository :
    IDtoImportRepository<ApiResourceRoleImportDto>
{
    private readonly IStorage<ApiResourceExt> _apiResourceStorage;
    private readonly IStorage<ApiResourceRole> _roleStorage;
    private readonly IPermissionChecker _permissionChecker;
    private readonly ILogger<ApiResourceImportDtoRepository> _logger;
    private readonly IRoleMappingValidationService _roleMappingValidationService;

    public ApiResourceImportDtoRepository(
        IStorage<ApiResourceExt> apiResourceStorage,
        IStorage<ApiResourceRole> roleStorage,
        IPermissionChecker permissionChecker,
        ILogger<ApiResourceImportDtoRepository> logger,
        IRoleMappingValidationService roleMappingValidationService)
    {
        _apiResourceStorage = apiResourceStorage;
        _roleStorage = roleStorage;
        _permissionChecker = permissionChecker;
        _logger = logger;
        _roleMappingValidationService = roleMappingValidationService;
    }

    public async Task<OperationStatus> ImportAsync(ClaimsPrincipal user, int id, ApiResourceRoleImportDto resource)
    {
        var currentApiResource = await _apiResourceStorage.GetByIdAsync(id) ?? throw new EntityNotFoundException($"API Resource with Id {id} was not found.");
        _ = await _permissionChecker.GetAccessRoleOrThrowIfNoAccessToEnvAsync(user, currentApiResource.SystemPermissionEnvironmentId, EntityAccessType.Update, currentApiResource.ToString()!);

        var validationSummary = await ValidateImportImplAsync(id, resource);
        if (validationSummary.HasErrors)
        {
            throw new ImportValidationException("Role mappings are invalid.", validationSummary);
        }

        switch (resource.ImportStrategy)
        {
            case ImportStrategy.Replace:
                await ReplaceApiResourceRoles(resource, currentApiResource);
                break;
            case ImportStrategy.Add:
                await MergeAddApiResourceRoles(resource, currentApiResource);
                break;
            default:
                throw new ImportValidationException("Unknown import strategy for API Resource roles.", validationSummary);
        }

        validationSummary.IsCompleted = true;

        return validationSummary;
    }

    public async Task<OperationStatus> ValidateImportAsync(ClaimsPrincipal user, int id, ApiResourceRoleImportDto resource)
    {
        var currentApiResource = await _apiResourceStorage.GetByIdAsync(id) ?? throw new EntityNotFoundException($"API Resource with Id {id} was not found.");
        _ = await _permissionChecker.GetAccessRoleOrThrowIfNoAccessToEnvAsync(user, currentApiResource.SystemPermissionEnvironmentId, EntityAccessType.Read, currentApiResource.ToString()!);

        return await ValidateImportImplAsync(id, resource);
    }

    internal async Task<OperationStatus> ValidateImportImplAsync(int id, ApiResourceRoleImportDto resource)
    {
        var validationSummary = new OperationStatus();

        // validate the logical structural integrity of the import
        RoleImportDtoValidationService<ApiResourceRoleMappingValueObject>.IsValid(resource, validationSummary);

        // validate values and descriptions
        await _roleMappingValidationService.ValidateImportRoleMappingsAsync(resource.Roles.SelectMany(r => r.Mappings).Cast<RoleMappingValueObject>().ToList(), validationSummary);

        _logger.LogInformation("Validating import for API Resource {ApiResourceId} with {NumberOfRoles} roles and {NumberOfRoleMappings} mappings. Validation summary: {ValidationSummary}",
            id, resource.Roles.Count, resource.Roles.SelectMany(r => r.Mappings).Count(), validationSummary);

        return validationSummary;
    }

    /// <summary>
    /// COMPLETELY replacing the existing roles with the new ones.
    /// </summary>
    internal async Task ReplaceApiResourceRoles(ApiResourceRoleImportDto resource, ApiResourceExt currentApiResource)
    {
        _logger.LogInformation("Replacing {NumberOfRoles} and {NumberOfRoleMappings} for API Resource {ApiResourceName} (Id: {ApiResourceId}) with imported {NumberOfImportedRoles} and {NumberOfImportedRoleMappings}.",
            currentApiResource.Roles.Count, currentApiResource.Roles.SelectMany(r => r.Mappings).Count(), currentApiResource.Name, currentApiResource.Id, resource.Roles.Count, resource.Roles.SelectMany(r => r.Mappings).Count());

        await RemoveAllExistingRoles(currentApiResource);

        foreach (var roleToImport in resource.Roles)
        {
            currentApiResource.Roles.Add(new ApiResourceRole
            {
                RoleName = roleToImport.RoleName
            });
        }

        foreach (var roleToImport in resource.Roles)
        {
            var roleToUpdate = currentApiResource.Roles.First(r => string.Equals(r.RoleName, roleToImport.RoleName, StringComparison.OrdinalIgnoreCase));

            roleToUpdate.Mappings.AddRange(roleToImport.Mappings.Select(mapping => new RoleMapping
            {
                ApiResourceRoleId = roleToUpdate.Id,
                Role = roleToUpdate,
                MappingType = Enum.Parse<RoleMapType>(mapping.MappingType),
                RoleMappingTypeId = (int)Enum.Parse<RoleMapType>(mapping.MappingType),
                Value = mapping.Value,
                Description = mapping.Description,
            }));
        }

        await _apiResourceStorage.UpdateAsync(currentApiResource);
    }

    private async Task RemoveAllExistingRoles(ApiResourceExt currentApiResource)
    {
        // Update audit timestamps on the role and all its mappings before deletion
        var updatedTime = DateTime.UtcNow;

        foreach (var role in currentApiResource.Roles)
        {
            role.Updated = updatedTime;
            if (role.Mappings != null)
            {
                foreach (var mapping in role.Mappings)
                {
                    mapping.Updated = updatedTime;
                }
            }
            await _roleStorage.UpdateAsync(role);
        }

        currentApiResource.Roles.Clear();
    }

    /// <summary>
    /// Merges imported roles and mappings into the existing API resource.
    /// Adds new roles, updates mappings for existing roles, and leaves untouched roles as-is.
    /// Does not remove any existing roles or mappings.
    /// </summary>
    internal async Task MergeAddApiResourceRoles(ApiResourceRoleImportDto resource, ApiResourceExt currentApiResource)
    {
        _logger.LogInformation(
            "Merging (add) {NumberOfImportedRoles} roles and {NumberOfImportedRoleMappings} mappings into API Resource {ApiResourceName} (Id: {ApiResourceId}). Existing roles: {NumberOfRoles}, mappings: {NumberOfRoleMappings}.",
            resource.Roles.Count,
            resource.Roles.SelectMany(r => r.Mappings).Count(),
            currentApiResource.Name,
            currentApiResource.Id,
            currentApiResource.Roles.Count,
            currentApiResource.Roles.SelectMany(r => r.Mappings).Count()
        );

        // Add or update roles
        foreach (var roleNameToImport in resource.Roles.Select(roleToImport => roleToImport.RoleName))
        {
            var existingRole = currentApiResource.Roles.FirstOrDefault(r => string.Equals(r.RoleName, roleNameToImport, StringComparison.OrdinalIgnoreCase));

            if (existingRole == null)
            {
                // Add new role
                var newRole = new ApiResourceRole
                {
                    RoleName = roleNameToImport
                };
                currentApiResource.Roles.Add(newRole);
            }
        }

        // Add mappings to roles (only add new mappings, do not remove or update existing ones)
        foreach (var roleToImport in resource.Roles)
        {
            var roleToUpdate = currentApiResource.Roles.First(r => string.Equals(r.RoleName, roleToImport.RoleName, StringComparison.OrdinalIgnoreCase));

            foreach (var mapping in roleToImport.Mappings)
            {
                // Only add mapping if it does not already exist (by MappingType and Value)
                bool mappingExists = roleToUpdate.Mappings.Any(m =>
                    m.MappingType == Enum.Parse<RoleMapType>(mapping.MappingType) &&
                    string.Equals(m.Value, mapping.Value, StringComparison.OrdinalIgnoreCase));

                if (!mappingExists)
                {
                    roleToUpdate.Mappings.Add(new RoleMapping
                    {
                        ApiResourceRoleId = roleToUpdate.Id,
                        Role = roleToUpdate,
                        MappingType = Enum.Parse<RoleMapType>(mapping.MappingType),
                        RoleMappingTypeId = (int)Enum.Parse<RoleMapType>(mapping.MappingType),
                        Value = mapping.Value,
                        Description = mapping.Description,
                    });
                }
            }
        }

        await _apiResourceStorage.UpdateAsync(currentApiResource);
    }
}
