// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

using System.Linq.Expressions;
using System.Security.Claims;
using AutoMapper;
using Microsoft.EntityFrameworkCore;
using IdentityServer.Abstraction.Contracts;
using IdentityServer.Abstraction.DTO.SystemPermissions;
using IdentityServer.Abstraction.Entities.IdentityServerConfig.SystemPermissions;
using IdentityServer.Abstraction.Exceptions;
using IdentityServer.Abstraction.Extensions;
using IdentityServer.Data.DuendeEntityExtensions;

namespace IdentityServer.Data.Repositories.DtoRepositories;

/// <summary>
/// Responsible for DTO mapping and access security checks for <seealso cref="SystemPermission"/> entities.
/// </summary>
internal class SystemPermissionDtoRepository :
    IDtoCreateRepository<SystemPermissionDtoRead, SystemPermissionDtoCreate>,
    IDtoReadRepository<SystemPermissionDtoRead>,
    IDtoListRepository<SystemPermissionShortDtoRead, SystemPermission>,
    IDtoUpdateRepository<SystemPermissionDtoRead, SystemPermissionDtoUpdate>
{
    private readonly IStorage<SystemPermission> _systemStorage;
    private readonly IStorage<ClientExt> _clientStorage;
    private readonly IStorage<ApiResourceExt> _apiResourceStorage;
    private readonly IMapper _mapper;
    private readonly IPermissionChecker _permissionChecker;
    private readonly ISystemPermissionAuditService _auditService;

    public SystemPermissionDtoRepository(
        IStorage<SystemPermission> systemStorage,
        IStorage<ClientExt> clientStorage,
        IStorage<ApiResourceExt> apiResourceStorage,
        IMapper mapper,
        IPermissionChecker permissionChecker,
        ISystemPermissionAuditService auditService)
    {
        _systemStorage = systemStorage;
        _clientStorage = clientStorage;
        _apiResourceStorage = apiResourceStorage;
        _mapper = mapper;
        _permissionChecker = permissionChecker;
        _auditService = auditService;
    }

    public async Task<SystemPermissionDtoRead> CreateAsync(ClaimsPrincipal user, SystemPermissionDtoCreate resource)
    {
        // anyone except Reader role can create System Permissions
        if (user.IsInRole(Abstraction.Constants.RoleNames.Reader) && !user.IsInRole(Abstraction.Constants.RoleNames.User) && !user.IsInRole(Abstraction.Constants.RoleNames.Admin))
        {
            throw new EntityAccessException(user, resource.ToString()!, EntityAccessType.Create);
        }

        var existingResource = await _systemStorage.FirstOrDefaultAsync(x => x.Name == resource.Name);
        if (existingResource != null)
        {
            throw new EntityAlreadyExistsException($"A System Permission '{existingResource.Name}' already exists.");
        }

        var systemPermission = _mapper.Map<SystemPermission>(resource);

        systemPermission.Created = DateTime.UtcNow;

        var storedSystemPermission = await _systemStorage.AddAsync(systemPermission);

        return MapStoredItemToDto(storedSystemPermission, SystemPermissionRoleType.Writer);
    }

    public async Task<int?> DeleteAsync(ClaimsPrincipal user, int id)
    {
        var entity = await _systemStorage.GetByIdAsync(id);
        if (entity == null) { return null; }

        _permissionChecker.GetAccessRoleOrThrowIfNoAccessToSystem(user, entity, EntityAccessType.Delete, entity.ToString()!);

        // block deletion of in-use permission
        var registrationsCount = await GetEnvironmentRegistrationsCount(entity.Environments.Select(x => x.Id).ToArray());
        if (registrationsCount > 0)
        {
            throw new EntityReferenceException($"The System Permission '{entity.Name}' is already assigned to {registrationsCount} Applications and/or API Resources, please delete all references before removing the permission.");
        }

        // 2-step approach to capture who deleted the system permission
        SetUpdatedAuditFieldsRecursive(entity);
        await _systemStorage.UpdateAsync(entity);
        return await _systemStorage.DeleteAsync(entity);
    }

    public async Task<SystemPermissionDtoRead> UpdateAsync(ClaimsPrincipal user, SystemPermissionDtoUpdate resource)
    {
        var entity = await _systemStorage.GetByIdAsync(resource.Id) ?? throw new EntityNotFoundException($"System Permission '{resource.Id}' doesn't exist!");

        var role = _permissionChecker.GetAccessRoleOrThrowIfNoAccessToSystem(user, entity, EntityAccessType.Update, entity.ToString()!);

        // the only field that can be updated is Description
        entity.Description = resource.Description;
        entity.Updated = DateTime.UtcNow;

        var storedItem = await _systemStorage.UpdateAsync(entity);

        var result = MapStoredItemToDto(storedItem, role);
        result.Updated = DateTime.UtcNow;
        result.UpdateReason = "System Permission";
        return result;
    }

    public Task<IQueryable<SystemPermissionShortDtoRead>> GetQueryableAsync(ClaimsPrincipal user)
    {
        return GetQueryableAsync(user, null);
    }

    [System.Diagnostics.CodeAnalysis.SuppressMessage("SonarQube", "S3358:Ternary operators should not be nested", Justification = "Complex access level logic requires nested ternary for SQL translatability")]
    [System.Diagnostics.CodeAnalysis.SuppressMessage("SonarQube", "S3776:Refactor this method to reduce its Cognitive Complexity", Justification = "Expression trees required for SQL translatability")]
    public async Task<IQueryable<SystemPermissionShortDtoRead>> GetQueryableAsync(ClaimsPrincipal user, Expression<Func<SystemPermission, bool>>? filter)
    {
        // 1. Pre-fetch async dependencies (permissions)
        var userObjectId = user.GetUserObjectId();
        var isAdmin = user.IsInRole(Abstraction.Constants.RoleNames.Admin);
        var isUser = user.IsInRole(Abstraction.Constants.RoleNames.User);

        // 2. Build the deferred query
        var query = _systemStorage.ShallowQuery();

        // 3. Apply filter
        if (filter != null)
        {
            query = query.Where(filter);
        }

        // 4. Project to DTO using two-step projection for readability while maintaining SQL translatability
        return query
            .Select(item => new
            {
                item.Id,
                item.Name,
                item.Description,
                item.Created,
                item.CreatedBy,
                item.Updated,
                item.UpdatedBy,
                item.Environments,
                // Pre-compute access level conditions
                AllEnvironmentsBlank = !item.Environments.Any(e => e.Permissions.Count != 0),
                HasWriterOnAllNonBlank = item.Environments
                    .Where(e => e.Permissions.Count != 0)
                    .All(e => e.Permissions.Any(p => p.OId == userObjectId && p.RoleType == SystemPermissionRoleType.Writer)),
                HasAnyPermissionOnNonBlank = item.Environments
                    .Where(e => e.Permissions.Count != 0)
                    .Any(e => e.Permissions.Any(p => p.OId == userObjectId)),
                HasAnyPermission = item.Environments
                    .SelectMany(e => e.Permissions)
                    .Any(p => p.OId == userObjectId)
            })
            .Select(x => new SystemPermissionShortDtoRead
            {
                Id = x.Id,
                Name = x.Name,
                Description = x.Description,
                EnvironmentIds = x.Environments.Select(e => e.Id).ToList(),
                EnvironmentNamesList = x.Environments.Select(e => e.Environment).ToList(),
                OwnersList = x.Environments
                    .SelectMany(e => e.Permissions)
                    .Where(p => p.RoleType == SystemPermissionRoleType.Writer)
                    .GroupBy(p => new { p.OId, p.Name })
                    .Where(g => g.Count() == x.Environments.Count)
                    .Select(g => g.Key.Name)
                    .OrderBy(n => n)
                    .ToList(),
                AccessLevel =
                    isAdmin ? SystemPermissionRoleType.Writer :
                    isUser ? (
                        x.AllEnvironmentsBlank ? SystemPermissionRoleType.Writer :
                        x.HasWriterOnAllNonBlank ? SystemPermissionRoleType.Writer :
                        x.HasAnyPermissionOnNonBlank ? SystemPermissionRoleType.Reader :
                        SystemPermissionRoleType.None
                    ) :
                    x.HasAnyPermission ? SystemPermissionRoleType.Reader :
                    SystemPermissionRoleType.None,
                Created = x.Created,
                CreatedBy = x.CreatedBy,
                Updated = x.Updated,
                UpdatedBy = x.UpdatedBy
            });
    }

    public async Task PostProcess(List<SystemPermissionShortDtoRead>? items)
    {
        if (items == null || items.Count == 0)
        {
            return;
        }

        // Collect all environment IDs across all items
        var allEnvIds = items
            .SelectMany(i => i.EnvironmentIds)
            .Distinct()
            .ToArray();

        if (allEnvIds.Length == 0)
        {
            return;
        }

        var (clientCounts, apiResourceCounts) = await GetEnvironmentRegistrationCountsAsync(allEnvIds);

        foreach (var item in items)
        {
            item.TotalRegistrations = item.EnvironmentIds
                .Sum(envId =>
                    clientCounts.GetValueOrDefault(envId, 0) +
                    apiResourceCounts.GetValueOrDefault(envId, 0));
        }
    }

    public async Task<SystemPermissionDtoRead?> GetByIdAsync(ClaimsPrincipal user, int id)
    {
        var entity = await _systemStorage.GetByIdAsync(id);
        if (entity == null)
        {
            return null;
        }

        var role = _permissionChecker.GetAccessRoleOrThrowIfNoAccessToSystem(user, entity, EntityAccessType.Read, entity.ToString()!);

        var result = MapStoredItemToDto(entity, role);

        // Populate LastModified from stored procedure
        var lastModifiedInfo = await _auditService.GetLastModifiedByIdAsync(id);
        if (lastModifiedInfo != null)
        {
            result.Updated = lastModifiedInfo.LastModified;
            result.UpdateReason = lastModifiedInfo.Reason;
        }

        var envIds = result.Environments.Select(e => e.Id).ToArray();
        if (envIds.Length > 0)
        {
            var (clientCounts, apiResourceCounts) = await GetEnvironmentRegistrationCountsAsync(envIds);

            foreach (var env in result.Environments)
            {
                env.ClientCount = clientCounts.GetValueOrDefault(env.Id, 0);
                env.ApiResourceCount = apiResourceCounts.GetValueOrDefault(env.Id, 0);
            }
        }

        return result;
    }

    private async Task<(Dictionary<int, int> ClientCounts, Dictionary<int, int> ApiResourceCounts)> GetEnvironmentRegistrationCountsAsync(int[] envIds)
    {
        var clientCounts = await _clientStorage.ShallowQuery()
            .Where(x => envIds.Contains(x.SystemPermissionEnvironmentId))
            .GroupBy(x => x.SystemPermissionEnvironmentId)
            .Select(g => new { EnvId = g.Key, Count = g.Count() })
            .ToDictionaryAsync(x => x.EnvId, x => x.Count);

        var apiResourceCounts = await _apiResourceStorage.ShallowQuery()
            .Where(x => envIds.Contains(x.SystemPermissionEnvironmentId))
            .GroupBy(x => x.SystemPermissionEnvironmentId)
            .Select(g => new { EnvId = g.Key, Count = g.Count() })
            .ToDictionaryAsync(x => x.EnvId, x => x.Count);

        return (clientCounts, apiResourceCounts);
    }

    private async Task<int> GetEnvironmentRegistrationsCount(int[] envIds)
    {
        return await _clientStorage.CountAsync(x => envIds.Contains(x.SystemPermissionEnvironmentId)) +
               await _apiResourceStorage.CountAsync(x => envIds.Contains(x.SystemPermissionEnvironmentId));
    }

    private SystemPermissionDtoRead MapStoredItemToDto(SystemPermission storedItem, SystemPermissionRoleType role)
    {
        var result = _mapper.Map<SystemPermissionDtoRead>(storedItem);
        result.AccessLevel = role;
        return result;
    }

    private static void SetUpdatedAuditFieldsRecursive(SystemPermission entity)
    {
        var updatedTime = DateTime.UtcNow;
        entity.Updated = updatedTime;
        SetUpdatedAuditFieldForEnvironments(entity, updatedTime);
    }

    private static void SetUpdatedAuditFieldForEnvironments(SystemPermission entity, DateTime updatedTime)
    {
        if (entity.Environments != null)
        {
            foreach (var environment in entity.Environments)
            {
                environment.Updated = updatedTime;
                SetUpdatedAuditFieldForPermissions(environment, updatedTime);
            }
        }
    }

    private static void SetUpdatedAuditFieldForPermissions(SystemPermissionEnvironment environment, DateTime updatedTime)
    {
        if (environment.Permissions != null)
        {
            foreach (var permission in environment.Permissions)
            {
                permission.Updated = updatedTime;
            }
        }
    }
}
