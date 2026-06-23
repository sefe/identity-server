// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

using IdentityServer.Abstraction.Entities.IdentityServerConfig.SystemPermissions;

namespace IdentityServer.Tests.Common.Builders;

public class SystemPermissionBuilder
{
    private readonly SystemPermission _systemPermission;
    private readonly List<SystemPermissionEnvironment> _environments = new();

    public SystemPermissionBuilder()
    {
        _systemPermission = new SystemPermission
        {
            Id = 1,
            Name = "sys",
            Description = "desc",
            Environments = new List<SystemPermissionEnvironment>()
        };
    }

    public SystemPermissionBuilder WithId(int id)
    {
        _systemPermission.Id = id;
        return this;
    }

    public SystemPermissionBuilder WithName(string name)
    {
        _systemPermission.Name = name;
        return this;
    }

    public SystemPermissionBuilder WithDescription(string description)
    {
        _systemPermission.Description = description;
        return this;
    }

    public SystemPermissionBuilder AddEnvironment(int id, string environmentName, List<SystemPermissionRole> permissions)
    {
        if (permissions == null || permissions.Count == 0)
        {
            throw new ArgumentException("Permissions cannot be null or empty", nameof(permissions));
        }
        var env = new SystemPermissionEnvironment
        {
            Id = id,
            Environment = environmentName,
            Permissions = permissions,
            SystemPermission = _systemPermission,
            SystemPermissionId = _systemPermission.Id,
        };
        _environments.Add(env);
        return this;
    }

    public SystemPermission Build()
    {
        _systemPermission.Environments = _environments;
        return _systemPermission;
    }
}
