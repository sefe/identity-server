// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

using IdentityServer.Abstraction.Entities.IdentityServerConfig.SystemPermissions;

namespace IdentityServer.Abstraction.Contracts;

public interface IHasEnvironment
{
    int SystemPermissionId { get; set; }
    string SystemPermissionName { get; set; }

    int SystemPermissionEnvironmentId { get; set; }
    string SystemPermissionEnvironmentName { get; set; }

    public SystemPermissionRoleType AccessLevel { get; set; }
}
