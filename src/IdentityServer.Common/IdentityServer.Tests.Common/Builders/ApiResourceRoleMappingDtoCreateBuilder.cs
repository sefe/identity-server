using IdentityServer.Abstraction.DTO.ApiResources;
using IdentityServer.Abstraction.Entities.IdentityServerConfig;

namespace IdentityServer.Tests.Common.Builders;

public class ApiResourceRoleMappingDtoCreateBuilder
{
    private readonly ApiResourcePropertyRoleMappingDtoCreate _roleMapping;

    public ApiResourceRoleMappingDtoCreateBuilder(RoleMapType mappingType)
    {
        _roleMapping = new ApiResourcePropertyRoleMappingDtoCreate
        {
            MappingType = mappingType,
            Value = string.Empty
        };
    }

    public ApiResourceRoleMappingDtoCreateBuilder WithApiResourceId(int apiResourceId)
    {
        _roleMapping.ApiResourceId = apiResourceId;
        return this;
    }

    public ApiResourceRoleMappingDtoCreateBuilder WithApiResourceRoleId(int apiResourceRoleId)
    {
        _roleMapping.ApiResourceRoleId = apiResourceRoleId;
        return this;
    }

    public ApiResourceRoleMappingDtoCreateBuilder WithValue(string value)
    {
        _roleMapping.Value = value;
        return this;
    }

    public ApiResourcePropertyRoleMappingDtoCreate Build()
    {
        return _roleMapping;
    }
}
