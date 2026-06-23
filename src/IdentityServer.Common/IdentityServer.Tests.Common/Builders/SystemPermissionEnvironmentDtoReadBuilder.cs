// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

using IdentityServer.Abstraction.DTO.SystemPermissions;
using IdentityServer.Abstraction.Entities.IdentityServerConfig.SystemPermissions;

namespace IdentityServer.Tests.Common.Builders;

public class SystemPermissionEnvironmentDtoReadBuilder
{
    private static int _uniqueIdCounter = 0;

    private readonly SystemPermissionEnvironmentDtoRead _environment;
    private readonly SystemPermissionDtoReadBuilder _parent;

    public SystemPermissionEnvironmentDtoReadBuilder(SystemPermissionDtoReadBuilder parent, int systemPermissionId, string systemPermissionName, string environment)
    {
        _environment = new SystemPermissionEnvironmentDtoRead
        {
            Id = Interlocked.Increment(ref _uniqueIdCounter),
            SystemPermissionId = systemPermissionId,
            SystemPermissionName = systemPermissionName,
            Environment = environment
        };
        _parent = parent;
    }

    public SystemPermissionEnvironmentDtoReadBuilder AddPermission(string oId, string name, SystemPermissionRoleType roleType)
    {
        _environment.Permissions.Add(new SystemPermissionRoleDtoReadBuilder(_environment.Id, oId, name, roleType).Build());
        return this;
    }

    public SystemPermissionDtoReadBuilder Build()
    {
        _parent.AddEnvironment(_environment);
        return _parent;
    }
}
