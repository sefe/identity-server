using System.Linq.Expressions;
using System.Security.Claims;
using AutoMapper;
using IdentityServer.Abstraction.Contracts;
using IdentityServer.Abstraction.DTO;
using IdentityServer.Abstraction.DTO.Clients;
using IdentityServer.Abstraction.Entities.IdentityServerConfig;
using IdentityServer.Abstraction.Entities.IdentityServerConfig.SystemPermissions;
using IdentityServer.Abstraction.Exceptions;
using IdentityServer.Data.DuendeEntityExtensions;
using IdentityServer.Data.Entities.Roles;
using DataEntities = Duende.IdentityServer.EntityFramework.Entities;

namespace IdentityServer.Data.Repositories.DtoRepositories.Client;

/// <summary>
/// Responsible for DTO mapping and access security checks for <seealso cref="ClientExt"/> entities.
/// </summary>
internal class ClientDtoRepository :
    IDtoCreateRepository<ClientDtoRead, ClientDtoCreate>,
    IDtoReadRepository<ClientDtoRead>,
    IDtoListRepository<ClientShortDtoRead, ClientExt>,
    IDtoUpdateRepository<ClientDtoRead, ClientDtoUpdate>
{
    private readonly IStorage<ClientExt> _clientStorage;
    private readonly IStorage<ApiScopeExt> _apiScopeStorage;
    private readonly IMapper _mapper;
    private readonly IPermissionChecker _permissionChecker;
    private readonly IStorage<ApiResourceExt> _apiResourceRepo;
    private readonly IStorage<ApiResourceRole> _apiResourceRoleRepo;
    private readonly ICache<DataEntities.Client> _clientCache;
    private readonly IClientAuditService _auditService;

#pragma warning disable IDE0079 // Remove unnecessary suppression
#pragma warning disable S107 // Method has too many parameters
    public ClientDtoRepository(
        IStorage<ClientExt> clientStorage,
        IStorage<ApiScopeExt> apiScopeStorage,
        IMapper mapper,
        IPermissionChecker permissionChecker,
        IStorage<ApiResourceExt> apiResourceRepo,
        IStorage<ApiResourceRole> apiResourceRoleRepo,
        ICache<DataEntities.Client> clientCache,
        IClientAuditService auditService)
#pragma warning restore S107 // Method has too many parameters
#pragma warning restore IDE0079 // Remove unnecessary suppression
    {
        _clientStorage = clientStorage;
        _mapper = mapper;
        _permissionChecker = permissionChecker;
        _apiScopeStorage = apiScopeStorage;
        _apiResourceRepo = apiResourceRepo;
        _apiResourceRoleRepo = apiResourceRoleRepo;
        _clientCache = clientCache;
        _auditService = auditService;
    }

    public async Task<ClientDtoRead> CreateAsync(ClaimsPrincipal user, ClientDtoCreate resource)
    {
        var role = await _permissionChecker.GetAccessRoleOrThrowIfNoAccessToEnvAsync(user, resource.SystemPermissionEnvironmentId, EntityAccessType.Create, "Application");

        var existingResource = await _clientStorage.FirstOrDefaultAsync(x => x.ClientId == resource.ClientId);
        if (existingResource != null)
        {
            throw new EntityAlreadyExistsException($"Application '{existingResource.ClientId}' already exists.");
        }

        var client = _mapper.Map<ClientExt>(resource);

        client.Created = DateTime.UtcNow;
        if (client.AllowedGrantTypes.Any(gr => gr.GrantType == ClientGrantTypeNames.Grant_Implicit))
        {
            client.AllowAccessTokensViaBrowser = true; // required for Implicit flow to work
        }

        var storedClient = await _clientStorage.AddAsync(client);
        var result = _mapper.Map<ClientDtoRead>(storedClient);
        result.AccessLevel = role;
        return result;
    }

    public async Task<int?> DeleteAsync(ClaimsPrincipal user, int id)
    {
        var entity = await _clientStorage.GetByIdAsync(id);
        if (entity == null) { return null; }

        await _permissionChecker.GetAccessRoleOrThrowIfNoAccessToEnvAsync(user, entity.SystemPermissionEnvironmentId, EntityAccessType.Delete, entity.ToString()!);

        await ThrowIfAnyClientRoleMappingsExist(entity.ClientId);

        // 2-step approach to capture who deleted the client and all nested entities
        SetUpdatedAuditFieldsRecursive(entity);
        await _clientStorage.UpdateAsync(entity);
        var removedId = await _clientStorage.DeleteAsync(entity);

        await _clientCache.RemoveAsync(entity.ClientId);

        return removedId;
    }

    private async Task ThrowIfAnyClientRoleMappingsExist(string clientId)
    {
        var associatedApiResourceRoles = await _apiResourceRoleRepo.ToListAsync(
            x => x.Mappings.Any(y => y.MappingType == RoleMapType.ClientId && y.Value == clientId));

        if (associatedApiResourceRoles.Count != 0)
        {
            var referencingApiResourceIds = associatedApiResourceRoles.Select(y => y.ApiResourceId).ToHashSet();
            var apiResources = await _apiResourceRepo.ToListAsync(x => referencingApiResourceIds.Contains(x.Id));

            throw new EntityReferenceException("Unable to delete the application as the application is linked to existing API Resource Role Mappings." +
                                               $" Affected API Resources: '{string.Join("', '", apiResources.Select(x => x.Name))}'");
        }
    }

    public async Task<ClientDtoRead> UpdateAsync(ClaimsPrincipal user, ClientDtoUpdate resource)
    {
        var currentClient = await _clientStorage.GetByIdAsync(resource.Id) ?? throw new EntityNotFoundException($"Application with Id {resource.Id} was not found.");
        var role = await _permissionChecker.GetAccessRoleOrThrowIfNoAccessToEnvAsync(user, currentClient.SystemPermissionEnvironmentId, EntityAccessType.Update, currentClient.ToString()!);

        currentClient.Updated = DateTime.UtcNow;
        currentClient.ClientName = resource.ClientName ?? currentClient.ClientName;
        currentClient.Description = resource.Description ?? currentClient.Description;
        currentClient.Enabled = resource.Enabled ?? currentClient.Enabled;
        currentClient.RequirePkce = resource.RequirePkce ?? currentClient.RequirePkce;
        currentClient.RequireClientSecret = resource.RequireClientSecret ?? currentClient.RequireClientSecret;
        currentClient.AccessTokenType = (int?)resource.AccessTokenType ?? currentClient.AccessTokenType;

        UpdateOfflineAccess(currentClient, resource);

        var storedClient = await _clientStorage.UpdateAsync(currentClient);
        var result = _mapper.Map<ClientDtoRead>(storedClient);

        if (result.AllowedScopes?.Count > 0)
        {
            await PopulateScopes(result.AllowedScopes);
        }

        result.AccessLevel = role;

        await _clientCache.RemoveAsync(currentClient.ClientId);

        result.Updated = DateTime.UtcNow;
        result.UpdateReason = "Application";

        return result;
    }

    private static void UpdateOfflineAccess(ClientExt currentClient, ClientDtoUpdate resource)
    {
        if (resource.AllowOfflineAccess == true &&
            currentClient.AllowedGrantTypes.Any(cg => string.Equals(cg.GrantType, ClientGrantTypeNames.Grant_Implicit, StringComparison.OrdinalIgnoreCase)))
        {
            throw new InvalidOperationException("Refresh Token is not permitted for an application with Implicit Grant for security reasons");
        }
        currentClient.AllowOfflineAccess = resource.AllowOfflineAccess ?? currentClient.AllowOfflineAccess;
    }

    public Task<IQueryable<ClientShortDtoRead>> GetQueryableAsync(ClaimsPrincipal user)
    {
        return GetQueryableAsync(user, null);
    }

    public async Task<IQueryable<ClientShortDtoRead>> GetQueryableAsync(ClaimsPrincipal user, Expression<Func<ClientExt, bool>>? filter)
    {
        // 1. Pre-fetch async dependencies (permissions)
        HashSet<int>? allowedEnvIds = null;
        if (!user.IsInRole(Abstraction.Constants.RoleNames.Admin))
        {
            allowedEnvIds = await _permissionChecker.GetAllAccessiblePermissionEnvironmentsAsync(user, SystemPermissionRoleType.Reader);
        }

        // 2. Build the deferred query
        var query = _clientStorage.ShallowQuery();

        // 3. Apply filter
        if (filter != null)
        {
            query = query.Where(filter);
        }

        // 4. Project to DTO (EF Core will translate this to SQL)
        return query.Select(item => new ClientShortDtoRead
        {
            Id = item.Id,
            ClientId = item.ClientId,
            ClientName = item.ClientName,
            SystemPermissionId = item.SystemPermissionEnvironment.SystemPermissionId,
            SystemPermissionName = item.SystemPermissionEnvironment.SystemPermission.Name,
            SystemPermissionEnvironmentId = item.SystemPermissionEnvironmentId,
            SystemPermissionEnvironmentName = item.SystemPermissionEnvironment.Environment,
            SystemPermissionEnvironmentOwnersList = item.SystemPermissionEnvironment.Permissions.Where(p => p.RoleType == SystemPermissionRoleType.Writer).Select(p => p.Name).OrderBy(n => n).ToList(),
            AccessLevel = allowedEnvIds == null || allowedEnvIds.Contains(item.SystemPermissionEnvironmentId)
                ? SystemPermissionRoleType.Reader
                : SystemPermissionRoleType.None,
            Created = item.Created,
            CreatedBy = item.CreatedBy,
            Updated = item.Updated,
            UpdatedBy = item.UpdatedBy
        });
    }

    public async Task<ClientDtoRead?> GetByIdAsync(ClaimsPrincipal user, int id)
    {
        var entity = await _clientStorage.GetByIdAsync(id);
        if (entity == null)
        {
            return null;
        }

        var role = await _permissionChecker.GetAccessRoleOrThrowIfNoAccessToEnvAsync(user, entity.SystemPermissionEnvironmentId, EntityAccessType.Read, entity.ToString()!);

        var result = _mapper.Map<ClientDtoRead>(entity);
        result.AccessLevel = role;

        if (result.AllowedScopes?.Count > 0)
        {
            await PopulateScopes(result.AllowedScopes);
        }

        var lastModifiedInfo = await _auditService.GetLastModifiedByIdAsync(id);
        if (lastModifiedInfo != null)
        {
            result.Updated = lastModifiedInfo.LastModified;
            result.UpdateReason = lastModifiedInfo.Reason;
        }

        return result;
    }

    private async Task PopulateScopes(List<ClientPropertyScopeDtoRead> allowedScopes)
    {
        PopulateOidStandardScopes(allowedScopes);
        await PopulateApiScopesAsync(allowedScopes);
    }

    private static void PopulateOidStandardScopes(List<ClientPropertyScopeDtoRead> allowedScopes)
    {
        // OpenID Connect scopes are not present in the database and are mapped from well-known values.
        foreach (var clientScope in allowedScopes)
        {
            if (OidcScopeNames.OidcStandardScopeMapping.TryGetValue(clientScope.Scope, out var oidcScope))
            {
                clientScope.ApiScope = new ApiScopeDtoRead
                {
                    Enabled = true,
                    Name = oidcScope.Name,
                    DisplayName = oidcScope.DisplayName,
                    Required = oidcScope.Required
                };
            }
        }
    }

    private async Task PopulateApiScopesAsync(List<ClientPropertyScopeDtoRead> allowedScopes)
    {
        // Client AllowedScopes scopes has only Name and ClientId fields populated. The rest must be loaded from ApiScopes.
        var apiScopeNames = allowedScopes.Select(a => a.Scope).Except(OidcScopeNames.OidcStandardScopeIds).ToHashSet(StringComparer.Ordinal);
        if (apiScopeNames.Count != 0)
        {
            var dbScopes = (await _apiScopeStorage.ToListAsync(s => apiScopeNames.Contains(s.Name))).ToDictionary(s => s.Name, StringComparer.Ordinal);
            var apiResourcesNames = apiScopeNames.Select(GetApiNameFromScopeName).Distinct().ToList();
            var dbApiResources = (await _apiResourceRepo.ToListAsync(ar => apiResourcesNames.Contains(ar.Name))).ToDictionary(ar => ar.Name, StringComparer.Ordinal);

            foreach (var clientScope in allowedScopes)
            {
                if (dbScopes.TryGetValue(clientScope.Scope, out var apiScope))
                {
                    clientScope.ApiScope = _mapper.Map<ApiScopeDtoRead>(apiScope);
                }

                if (dbApiResources.TryGetValue(GetApiNameFromScopeName(clientScope.Scope), out var apiResource))
                {
                    clientScope.ApiResourceEnabled = apiResource.Enabled;
                }
            }
        }
    }

    private static string GetApiNameFromScopeName(string scopeName)
    {
        return scopeName.Split('.')[0];
    }

    #region Set Updated value for the object tree for audit purposes
    private static void SetUpdatedAuditFieldsRecursive(ClientExt entity)
    {
        var updatedTime = DateTime.UtcNow;
        entity.Updated = updatedTime;
        SetUpdatedAuditFieldForRoles(entity, updatedTime);
        SetUpdatedAuditFieldForSecrets(entity, updatedTime);
        SetUpdatedAuditFieldForScopes(entity, updatedTime);
        SetUpdatedAuditFieldForRedirectUris(entity, updatedTime);
        SetUpdatedAuditFieldForGrantTypes(entity, updatedTime);
        SetUpdatedAuditFieldForCorsOrigins(entity, updatedTime);
        SetUpdatedAuditFieldForEntraApps(entity, updatedTime);
    }

    private static void SetUpdatedAuditFieldForRoles(ClientExt entity, DateTime updatedTime)
    {
        if (entity.Roles != null)
        {
            foreach (var role in entity.Roles)
            {
                role.Updated = updatedTime;
                if (role.Mappings != null)
                {
                    foreach (var mapping in role.Mappings)
                    {
                        mapping.Updated = updatedTime;
                    }
                }
            }
        }
    }

    private static void SetUpdatedAuditFieldForSecrets(ClientExt entity, DateTime updatedTime)
    {
        if (entity.ClientSecrets != null)
        {
            foreach (var secret in entity.ClientSecrets)
            {
                if (secret is ClientSecretExt extSecret)
                {
                    extSecret.Updated = updatedTime;
                }
            }
        }
    }

    private static void SetUpdatedAuditFieldForScopes(ClientExt entity, DateTime updatedTime)
    {
        if (entity.AllowedScopes != null)
        {
            foreach (var scope in entity.AllowedScopes)
            {
                if (scope is ClientScopeExt extScope)
                {
                    extScope.Updated = updatedTime;
                }
            }
        }
    }

    private static void SetUpdatedAuditFieldForRedirectUris(ClientExt entity, DateTime updatedTime)
    {
        if (entity.RedirectUris != null)
        {
            foreach (var redirectUri in entity.RedirectUris)
            {
                if (redirectUri is ClientRedirectUriExt extRedirectUri)
                {
                    extRedirectUri.Updated = updatedTime;
                }
            }
        }

        if (entity.PostLogoutRedirectUris != null)
        {
            foreach (var redirectUri in entity.PostLogoutRedirectUris)
            {
                if (redirectUri is ClientPostLogoutRedirectUriExt extRedirectUri)
                {
                    extRedirectUri.Updated = updatedTime;
                }
            }
        }
    }

    private static void SetUpdatedAuditFieldForGrantTypes(ClientExt entity, DateTime updatedTime)
    {
        if (entity.AllowedGrantTypes != null)
        {
            foreach (var grantType in entity.AllowedGrantTypes)
            {
                if (grantType is ClientGrantTypeExt extGrantType)
                {
                    extGrantType.Updated = updatedTime;
                }
            }
        }
    }

    private static void SetUpdatedAuditFieldForCorsOrigins(ClientExt entity, DateTime updatedTime)
    {
        if (entity.AllowedCorsOrigins != null)
        {
            foreach (var corsOrigin in entity.AllowedCorsOrigins)
            {
                if (corsOrigin is ClientCorsOriginExt extCorsOrigin)
                {
                    extCorsOrigin.Updated = updatedTime;
                }
            }
        }
    }

    private static void SetUpdatedAuditFieldForEntraApps(ClientExt entity, DateTime updatedTime)
    {
        if (entity.EntraApps != null)
        {
            foreach (var entraApp in entity.EntraApps)
            {
                entraApp.Updated = updatedTime;
            }
        }
    }
    #endregion
}
