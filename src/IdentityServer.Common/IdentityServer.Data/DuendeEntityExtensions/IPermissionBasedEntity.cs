// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

using IdentityServer.Abstraction.Entities.IdentityServerConfig.SystemPermissions;

namespace IdentityServer.Data.DuendeEntityExtensions;

public interface IPermissionBasedEntity
{
    int SystemPermissionEnvironmentId { get; set; }

    SystemPermissionEnvironment SystemPermissionEnvironment { get; set; }
}
