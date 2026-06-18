using System.Diagnostics.CodeAnalysis;
using AutoMapper;
using IdentityServer.Abstraction.DTO;
using IdentityServer.Abstraction.DTO.ApiResources;
using IdentityServer.Abstraction.DTO.Clients;
using IdentityServer.Abstraction.DTO.SystemPermissions;
using IdentityServer.Abstraction.Entities.IdentityServerConfig.SystemPermissions;
using IdentityServer.Data.DuendeEntityExtensions;
using IdentityServer.Data.Entities.Roles;
using DataEntities = Duende.IdentityServer.EntityFramework.Entities;

namespace IdentityServer.Data.Configuration.Mappings;

[ExcludeFromCodeCoverage]
public class AdminUiConfigurationMapProfile : Profile
{
    public AdminUiConfigurationMapProfile()
    {
        CreateMap<ApiScopeExt, ApiScopeDtoRead>();

        ConfigureApiResourceMappings();

        ConfigureClientMappings();

        ConfigureSystemPermissionMappings();
    }

    private void ConfigureApiResourceMappings()
    {
        CreateMap<ApiResourceDtoCreate, ApiResourceExt>();
        CreateMap<ApiResourceExt, ApiResourceDtoRead>()
            .AfterMap((api, dto) =>
            {
                if (api.SystemPermissionEnvironment != null)
                {
                    dto.SystemPermissionId = api.SystemPermissionEnvironment.SystemPermissionId;
                    dto.SystemPermissionEnvironmentName = api.SystemPermissionEnvironment.Environment;
                    if (api.SystemPermissionEnvironment.SystemPermission != null)
                    {
                        dto.SystemPermissionName = api.SystemPermissionEnvironment.SystemPermission.Name;
                    }
                }
            });
        CreateMap<ApiResourceExt, ApiResourceShortDtoRead>()
            .AfterMap((api, dto) =>
            {
                if (api.SystemPermissionEnvironment != null)
                {
                    dto.SystemPermissionId = api.SystemPermissionEnvironment.SystemPermissionId;
                    dto.SystemPermissionEnvironmentName = api.SystemPermissionEnvironment.Environment;
                    if (api.SystemPermissionEnvironment.SystemPermission != null)
                    {
                        dto.SystemPermissionName = api.SystemPermissionEnvironment.SystemPermission.Name;
                    }
                }
            });
        CreateMap<ApiResourcePropertyScopeDtoCreate, ApiScopeExt>()
            .AfterMap((createDto, apiScope) =>
            {
                apiScope.ShowInDiscoveryDocument = false;
                apiScope.Emphasize = false;
            });
        CreateMap<ApiResourcePropertyScopeDtoUpdate, ApiScopeExt>();
        CreateMap<ApiResourceScopeExt, ApiResourcePropertyScopeDtoRead>();
        CreateMap<ApiResourceSecretExt, ApiResourcePropertySecretDtoRead>();
        CreateMap<ApiResourceSecretExt, ApiResourcePropertySecretValueDtoRead>();
        CreateMap<ApiResourcePropertySecretDtoCreate, ApiResourceSecretExt>();
        CreateMap<ApiResourceRole, ApiResourcePropertyRoleDtoRead>();
        CreateMap<ApiResourcePropertyRoleDtoCreate, ApiResourceRole>();
        CreateMap<RoleMapping, ApiResourcePropertyRoleMappingDtoRead>();
        CreateMap<ApiResourcePropertyRoleMappingDtoCreate, RoleMapping>()
            .AfterMap((createDto, roleMapping) =>
            {
                roleMapping.RoleMappingTypeId = (int)roleMapping.MappingType;
            });

        CreateMap<DataEntities.ApiResource, ApiResourceExt>()
            .ForMember(dest => dest.SystemPermissionEnvironmentId, opt => opt.Ignore())
            .ForMember(dest => dest.SystemPermissionEnvironment, opt => opt.Ignore())
            .ReverseMap();
    }

    private void ConfigureClientMappings()
    {
        CreateMap<ClientDtoCreate, ClientExt>()
            .ForMember(dest => dest.AllowedGrantTypes,
                opt => opt.MapFrom(src => src.AllowedGrantTypes.Select(gt => new ClientGrantTypeExt { GrantType = gt }).ToList()));
        CreateMap<ClientExt, ClientDtoRead>()
            .AfterMap((client, dto) =>
            {
                if (client.SystemPermissionEnvironment != null)
                {
                    dto.SystemPermissionId = client.SystemPermissionEnvironment.SystemPermissionId;
                    dto.SystemPermissionEnvironmentName = client.SystemPermissionEnvironment.Environment;
                    if (client.SystemPermissionEnvironment.SystemPermission != null)
                    {
                        dto.SystemPermissionName = client.SystemPermissionEnvironment.SystemPermission.Name;
                    }
                }
            });
        CreateMap<ClientExt, ClientShortDtoRead>()
            .AfterMap((client, dto) =>
            {
                if (client.SystemPermissionEnvironment != null)
                {
                    dto.SystemPermissionId = client.SystemPermissionEnvironment.SystemPermissionId;
                    dto.SystemPermissionEnvironmentName = client.SystemPermissionEnvironment.Environment;
                    if (client.SystemPermissionEnvironment.SystemPermission != null)
                    {
                        dto.SystemPermissionName = client.SystemPermissionEnvironment.SystemPermission.Name;
                    }
                }
            });
        CreateMap<ClientExt, ClientDtoSearchResponse>();
        CreateMap<ClientCorsOriginExt, ClientPropertyCorsOriginDtoRead>();
        CreateMap<ClientPropertyCorsOriginDtoCreate, ClientCorsOriginExt>();
        CreateMap<ClientGrantTypeExt, ClientPropertyGrantDtoRead>();
        CreateMap<ClientPropertyGrantDtoCreate, ClientGrantTypeExt>();
        CreateMap<ClientEntraApp, ClientPropertyEntraAppDtoRead>();
        CreateMap<ClientPropertyEntraAppDtoCreate, ClientEntraApp>();
        CreateMap<ClientRedirectUriExt, ClientPropertyRedirectUriDtoRead>();
        CreateMap<ClientPropertyRedirectUriDtoCreate, ClientRedirectUriExt>();
        CreateMap<ClientPostLogoutRedirectUriExt, ClientPropertyPostLogoutRedirectUriDtoRead>();
        CreateMap<ClientPropertyPostLogoutRedirectUriDtoCreate, ClientPostLogoutRedirectUriExt>();
        CreateMap<ClientScopeExt, ClientPropertyScopeDtoRead>();
        CreateMap<ClientPropertyScopeDtoCreate, ClientScopeExt>();
        CreateMap<ClientSecretExt, ClientPropertySecretDtoRead>();
        CreateMap<ClientSecretExt, ClientPropertySecretValueDtoRead>();
        CreateMap<ClientPropertySecretDtoCreate, ClientSecretExt>();
        CreateMap<ClientPropertyRoleDtoCreate, ClientRole>();
        CreateMap<ClientRole, ClientPropertyRoleDtoRead>();
        CreateMap<ClientPropertyRoleMappingDtoCreate, ClientRoleMapping>();
        CreateMap<ClientRoleMapping, ClientPropertyRoleMappingDtoRead>();

        CreateMap<DataEntities.Client, ClientExt>()
            .ForMember(dest => dest.SystemPermissionEnvironmentId, opt => opt.Ignore())
            .ForMember(dest => dest.SystemPermissionEnvironment, opt => opt.Ignore())
            .ReverseMap();
    }

    private void ConfigureSystemPermissionMappings()
    {
        CreateMap<SystemPermissionDtoCreate, SystemPermission>();
        CreateMap<SystemPermissionDtoUpdate, SystemPermission>();
        CreateMap<SystemPermission, SystemPermissionDtoRead>();
        CreateMap<SystemPermission, SystemPermissionShortDtoRead>();
        CreateMap<SystemPermissionEnvironmentDtoCreate, SystemPermissionEnvironment>();
        CreateMap<SystemPermissionEnvironment, SystemPermissionEnvironmentDtoRead>()
            .AfterMap((spe, dto) =>
            {
                if (spe.SystemPermission != null)
                {
                    dto.SystemPermissionName = spe.SystemPermission.Name;
                }
            });
        CreateMap<SystemPermissionRoleDtoCreate, SystemPermissionRole>();
        CreateMap<SystemPermissionRoleDtoUpdate, SystemPermissionRole>();
        CreateMap<SystemPermissionRole, SystemPermissionRoleDtoRead>();
    }
}
