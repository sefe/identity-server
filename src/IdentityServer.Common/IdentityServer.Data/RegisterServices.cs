// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

using System.Diagnostics.CodeAnalysis;
using AutoMapper;
using Duende.IdentityServer.EntityFramework.DbContexts;
using Duende.IdentityServer.EntityFramework.Storage;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using IdentityServer.Abstraction.Contracts;
using IdentityServer.Abstraction.Contracts.MicrosoftGraph;
using IdentityServer.Abstraction.DTO.ApiResources;
using IdentityServer.Abstraction.DTO.Clients;
using IdentityServer.Abstraction.DTO.Import;
using IdentityServer.Abstraction.DTO.SystemPermissions;
using IdentityServer.Abstraction.Entities.IdentityServerConfig.SystemPermissions;
using IdentityServer.Core;
using IdentityServer.Data.Configuration.Mappings;
using IdentityServer.Data.DbContexts;
using IdentityServer.Data.DuendeEntityExtensions;
using IdentityServer.Data.Entities.Roles;
using IdentityServer.Data.Repositories.DtoRepositories;
using IdentityServer.Data.Repositories.DtoRepositories.ApiResource;
using IdentityServer.Data.Repositories.DtoRepositories.Client;
using IdentityServer.Data.Repositories.DtoRepositories.SystemPermissions;
using IdentityServer.Data.Repositories.Storage;
using IdentityServer.Data.Security;
using IdentityServer.Data.Services;

namespace IdentityServer.Data;

[ExcludeFromCodeCoverage]
public static class RegisterServices
{
    /// <summary>
    /// Admin UI (and test projects) use this method to add the configuration database context.
    /// </summary>
    /// <remarks>API uses Duende-provided data layer instead of this project.</remarks>
    /// <param name="services">The service collection</param>
    /// <param name="optionsBuilder">A delegate used to configure the options for the configuration database context. Cannot be null.</param>
    /// <returns>The same service collection instance so that additional calls can be chained.</returns>
    public static IServiceCollection AddConfigurationDbContext(this IServiceCollection services, Action<DbContextOptionsBuilder> optionsBuilder)
    {
        services.AddDbContextFactory<IdentityServerConfigurationDbContext>(optionsBuilder, ServiceLifetime.Scoped);
        services.AddConfigurationDbContext<IdentityServerConfigurationDbContext>(options =>
        {
            options.ConfigureDbContext = optionsBuilder;
        });

        services.AddDbContext<ConfigurationDbContext>(optionsBuilder);
        return services;
    }

    /// <summary>
    /// Identity Server API needs only basic storage registrations for role mappings.
    /// </summary>
    /// <param name="services">The service collection.</param>
    /// <returns>The same service collection instance so that additional calls can be chained.</returns>
    public static IServiceCollection AddDataLayerForApi(this IServiceCollection services)
    {
        services.AddSingleton(_ =>
        {
            var config = new MapperConfiguration(cfg => { cfg.AddProfile<IdentityServerApiConfigurationMapProfile>(); });
            return config.CreateMapper();
        });

        services.AddScoped<IStorage<ClientExt>, ClientStorage>();
        services.AddScoped<IStorage<ApiResourceExt>, ApiResourceStorage>();
        return services;
    }

    public static IServiceCollection AddDataLayerForUi(this IServiceCollection services)
    {
        services.AddSingleton<ISecretGeneratorService, SecretGeneratorService>();
        services.AddSingleton(_ =>
        {
            var config = new MapperConfiguration(cfg => { cfg.AddProfile<AdminUiConfigurationMapProfile>(); });
            return config.CreateMapper();
        });

        // Security
        services.AddScoped<IPermissionChecker, StandardPermissionChecker>();
        services.AddScoped<IUserGroupMembershipService, UserGroupMembershipService>(); // this needs Microsoft Entra services

        services.AddCommonEntities();

        services.AddApiResources();

        services.AddClients();

        services.AddSystemPermissions();

        services.AddHistoryServices();

        return services;
    }

    private static IServiceCollection AddCommonEntities(this IServiceCollection services)
    {
        services.AddScoped<IStorage<ApiScopeExt>, ApiScopeStorage>();
        services.AddScoped<IRoleMappingValidationService, RoleMappingValidationService>();

        return services;
    }

    private static IServiceCollection AddClients(this IServiceCollection services)
    {
        // Services
        services.AddScoped<IClientAuditService, ClientAuditService>();

        // Storage
        services.AddScoped<IStorage<ClientExt>, ClientStorage>();
        services.AddScoped<IStorage<ClientCorsOriginExt>, ClientPropertyCorsOriginStorage>();
        services.AddScoped<IStorage<ClientGrantTypeExt>, ClientPropertyGrantTypeStorage>();
        services.AddScoped<IStorage<ClientEntraApp>, ClientPropertyEntraAppStorage>();
        services.AddScoped<IStorage<ClientRedirectUriExt>, ClientPropertyRedirectUriStorage>();
        services.AddScoped<IStorage<ClientPostLogoutRedirectUriExt>, ClientPropertyPostLogoutRedirectUriStorage>();
        services.AddScoped<IStorage<ClientRole>, ClientPropertyRoleStorage>();
        services.AddScoped<IStorage<ClientRoleMapping>, ClientPropertyRoleMappingStorage>();
        services.AddScoped<IStorage<ClientScopeExt>, ClientPropertyScopeStorage>();
        services.AddScoped<IStorage<ClientSecretExt>, ClientPropertySecretStorage>();

        // Repositories
        services.AddScoped<IDtoCreateRepository<ClientDtoRead, ClientDtoCreate>, ClientDtoRepository>();
        services.AddScoped<IDtoCloneRepository<ClientDtoRead, ClientDtoClone>, ClientDtoCloneRepository>();
        services.AddScoped<IDtoReadRepository<ClientDtoRead>, ClientDtoRepository>();
        services.AddScoped<IDtoListRepository<ClientShortDtoRead, ClientExt>, ClientDtoRepository>();
        services.AddScoped<IDtoUpdateRepository<ClientDtoRead, ClientDtoUpdate>, ClientDtoRepository>();
        services.AddScoped<IDtoImportRepository<ClientRoleImportDto>, ClientImportDtoRepository>();
        services.AddScoped<IDtoCreateRepository<ClientPropertyCorsOriginDtoRead, ClientPropertyCorsOriginDtoCreate>, ClientPropertyCorsOriginDtoRepository>();
        services.AddScoped<IDtoCreateRepository<ClientPropertyGrantDtoRead, ClientPropertyGrantDtoCreate>, ClientPropertyGrantDtoRepository>();
        services.AddScoped<IDtoCreateRepository<ClientPropertyEntraAppDtoRead, ClientPropertyEntraAppDtoCreate>, ClientPropertyEntraAppDtoRepository>();
        services.AddScoped<IDtoCreateRepository<ClientPropertyRedirectUriDtoRead, ClientPropertyRedirectUriDtoCreate>, ClientPropertyRedirectUriDtoRepository>();
        services.AddScoped<IDtoCreateRepository<ClientPropertyPostLogoutRedirectUriDtoRead, ClientPropertyPostLogoutRedirectUriDtoCreate>, ClientPropertyPostLogoutRedirectUriDtoRepository>();
        services.AddScoped<IDtoCreateRepository<ClientPropertyRoleDtoRead, ClientPropertyRoleDtoCreate>, ClientPropertyRoleDtoRepository>();
        services.AddScoped<IDtoCreateRepository<ClientPropertyRoleMappingDtoRead, ClientPropertyRoleMappingDtoCreate>, ClientPropertyRoleMappingDtoRepository>();
        services.AddScoped<IDtoCreateRepository<ClientPropertySecretValueDtoRead, ClientPropertySecretDtoCreate>, ClientPropertySecretDtoRepository>();
        services.AddScoped<IDtoCreateRepository<ClientPropertyScopeDtoRead, ClientPropertyScopeDtoCreate>, ClientPropertyScopeDtoRepository>();

        // Parent Utils
        services.AddSingleton<IParentAccessor<ClientCorsOriginExt, ClientExt>, ClientParentAccessor>();
        services.AddSingleton<IParentAccessor<ClientGrantTypeExt, ClientExt>, ClientParentAccessor>();
        services.AddSingleton<IParentAccessor<ClientEntraApp, ClientExt>, ClientParentAccessor>();
        services.AddSingleton<IParentAccessor<ClientRedirectUriExt, ClientExt>, ClientParentAccessor>();
        services.AddSingleton<IParentAccessor<ClientPostLogoutRedirectUriExt, ClientExt>, ClientParentAccessor>();
        services.AddSingleton<IParentAccessor<ClientScopeExt, ClientExt>, ClientParentAccessor>();
        services.AddSingleton<IParentAccessor<ClientSecretExt, ClientExt>, ClientParentAccessor>();
        services.AddSingleton<IParentAccessor<ClientRole, ClientExt>, ClientParentAccessor>();
        services.AddSingleton<IParentAccessor<ClientRoleMapping, ClientRole>, ClientRoleParentAccessor>();

        return services;
    }

    private static IServiceCollection AddApiResources(this IServiceCollection services)
    {
        // Services
        services.AddScoped<IApiResourceAuditService, ApiResourceAuditService>();

        // Storage
        services.AddScoped<IStorage<ApiResourceExt>, ApiResourceStorage>();
        services.AddScoped<IStorage<ApiResourceScopeExt>, ApiResourcePropertyScopeStorage>();
        services.AddScoped<IStorage<ApiResourceRole>, ApiResourcePropertyRoleStorage>();
        services.AddScoped<IStorage<ApiResourceSecretExt>, ApiResourcePropertySecretStorage>();
        services.AddScoped<IStorage<RoleMapping>, ApiResourcePropertyRoleMappingStorage>();

        // Repositories
        services.AddScoped<IDtoCreateRepository<ApiResourceDtoRead, ApiResourceDtoCreate>, ApiResourceDtoRepository>();
        services.AddScoped<IDtoCloneRepository<ApiResourceDtoRead, ApiResourceDtoClone>, ApiResourceCloneDtoRepository>();
        services.AddScoped<IDtoReadRepository<ApiResourceDtoRead>, ApiResourceDtoRepository>();
        services.AddScoped<IDtoListRepository<ApiResourceShortDtoRead, ApiResourceExt>, ApiResourceDtoRepository>();
        services.AddScoped<IDtoUpdateRepository<ApiResourceDtoRead, ApiResourceDtoUpdate>, ApiResourceDtoRepository>();
        services.AddScoped<IDtoImportRepository<ApiResourceRoleImportDto>, ApiResourceImportDtoRepository>();
        services.AddScoped<IDtoCreateRepository<ApiResourcePropertyRoleDtoRead, ApiResourcePropertyRoleDtoCreate>, ApiResourcePropertyRoleDtoRepository>();
        services.AddScoped<IDtoCreateRepository<ApiResourcePropertyRoleMappingDtoRead, ApiResourcePropertyRoleMappingDtoCreate>, ApiResourcePropertyRoleMappingDtoRepository>();
        services.AddScoped<IDtoCreateRepository<ApiResourcePropertyScopeDtoRead, ApiResourcePropertyScopeDtoCreate>, ApiResourcePropertyScopeDtoRepository>();
        services.AddScoped<IDtoUpdateRepository<ApiResourcePropertyScopeDtoRead, ApiResourcePropertyScopeDtoUpdate>, ApiResourcePropertyScopeDtoRepository>();
        services.AddScoped<IDtoCreateRepository<ApiResourcePropertySecretValueDtoRead, ApiResourcePropertySecretDtoCreate>, ApiResourcePropertySecretDtoRepository>();

        // Parent Utils
        services.AddSingleton<IParentAccessor<ApiResourceRole, ApiResourceExt>, ApiResourceParentAccessor>();
        services.AddSingleton<IParentAccessor<ApiResourceScopeExt, ApiResourceExt>, ApiResourceParentAccessor>();
        services.AddSingleton<IParentAccessor<ApiResourceSecretExt, ApiResourceExt>, ApiResourceParentAccessor>();
        services.AddSingleton<IParentAccessor<RoleMapping, ApiResourceRole>, ApiResourceRoleParentAccessor>();

        return services;
    }

    private static IServiceCollection AddSystemPermissions(this IServiceCollection services)
    {
        // Services
        services.AddScoped<ISystemPermissionAuditService, SystemPermissionAuditService>();

        // Storage
        services.AddScoped<IStorage<SystemPermission>, SystemPermissionStorage>();
        services.AddScoped<IStorage<SystemPermissionEnvironment>, SystemPermissionEnvironmentStorage>();
        services.AddScoped<IStorage<SystemPermissionRole>, SystemPermissionRoleStorage>();

        // Repositories
        services.AddScoped<IDtoCreateRepository<SystemPermissionDtoRead, SystemPermissionDtoCreate>, SystemPermissionDtoRepository>();
        services.AddScoped<IDtoReadRepository<SystemPermissionDtoRead>, SystemPermissionDtoRepository>();
        services.AddScoped<IDtoListRepository<SystemPermissionShortDtoRead, SystemPermission>, SystemPermissionDtoRepository>();
        services.AddScoped<IDtoUpdateRepository<SystemPermissionDtoRead, SystemPermissionDtoUpdate>, SystemPermissionDtoRepository>();
        services.AddScoped<IDtoCreateRepository<SystemPermissionEnvironmentDtoRead, SystemPermissionEnvironmentDtoCreate>, SystemPermissionEnvironmentDtoRepository>();
        services.AddScoped<IDtoReadRepository<SystemPermissionEnvironmentDtoRead>, SystemPermissionEnvironmentDtoRepository>();
        services.AddScoped<IDtoListRepository<SystemPermissionEnvironmentDtoRead, SystemPermissionEnvironment>, SystemPermissionEnvironmentDtoRepository>();
        services.AddScoped<IDtoCreateRepository<SystemPermissionRoleDtoRead, SystemPermissionRoleDtoCreate>, SystemPermissionRoleDtoRepository>();
        services.AddScoped<IDtoUpdateRepository<SystemPermissionRoleDtoRead, SystemPermissionRoleDtoUpdate>, SystemPermissionRoleDtoRepository>();
        services.AddScoped<IDtoParentListRepository<SystemPermissionRoleDtoRead>, SystemPermissionRoleDtoRepository>();

        return services;
    }

    private static IServiceCollection AddHistoryServices(this IServiceCollection services)
    {
        services.AddScoped<IHistoryService, HistoryService>();

        // Register generic history repositories
        services.AddScoped<IClientHistoryRepository, ClientHistoryDtoRepository>();
        services.AddScoped<IApiResourceHistoryRepository, ApiResourceHistoryDtoRepository>();
        services.AddScoped<ISystemPermissionHistoryRepository, SystemPermissionHistoryDtoRepository>();

        return services;
    }
}
