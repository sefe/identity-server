using Duende.IdentityServer.EntityFramework.Entities;
using IdentityServer.Abstraction.Entities.IdentityServerConfig.SystemPermissions;
using IdentityServer.Data.DuendeEntityExtensions;
using IdentityServer.Data.Entities.Roles;

namespace IdentityServer.Tests.Common.Builders;

public class ApiResourceExtBuilder
{
    private readonly ApiResourceExt _apiResource;
    public ApiResourceExtBuilder(string name)
    {
        _apiResource = new ApiResourceExt
        {
            Name = name,
            DisplayName = name,
            Created = DateTime.UtcNow,
            ValidFrom = DateTime.UtcNow,
            ValidTo = DateTime.MaxValue,
            SystemPermissionEnvironment = new SystemPermissionEnvironment
            {
                Environment = SystemPermissionEnvironmentNames.Development,
                SystemPermission = new SystemPermission
                {
                    Name = "Default System Permission",
                    Description = "Default System Permission for testing purposes"
                }
            },
            Secrets = new List<ApiResourceSecret>(),
            Scopes = new List<ApiResourceScope>()
        };
    }

    public ApiResourceExtBuilder WithId(int id)
    {
        _apiResource.Id = id;
        return this;
    }

    public ApiResourceExtBuilder WithDisplayName(string displayName)
    {
        _apiResource.DisplayName = displayName;
        return this;
    }

    public ApiResourceExtBuilder WithCreated(DateTime created, string createdBy = null)
    {
        _apiResource.Created = created;
        _apiResource.CreatedBy = createdBy;
        return this;
    }

    public ApiResourceExtBuilder WithUpdated(DateTime updated, string updatedBy)
    {
        _apiResource.Updated = updated;
        _apiResource.UpdatedBy = updatedBy;
        return this;
    }

    public ApiResourceExtBuilder WithPeriod(DateTime periodStart, DateTime periodEnd)
    {
        _apiResource.ValidFrom = periodStart;
        _apiResource.ValidTo = periodEnd;
        return this;
    }

    public ApiResourceExtBuilder WithRole(string roleName, List<RoleMapping> mappings)
    {
        var role = new ApiResourceRole
        {
            RoleName = roleName,
            Mappings = mappings
        };
        _apiResource.Roles.Add(role);
        return this;
    }

    public ApiResourceExtBuilder WithSecret(string description)
    {
        var secret = new ApiResourceSecretExt()
        {
            Description = description
        };
        _apiResource.Secrets.Add(secret);
        return this;
    }

    public ApiResourceExtBuilder WithScope(string name)
    {
        var scope = new ApiResourceScope()
        {
            Scope = name
        };
        _apiResource.Scopes.Add(scope);
        return this;
    }

    public ApiResourceExt Build()
    {
        return _apiResource;
    }
}
