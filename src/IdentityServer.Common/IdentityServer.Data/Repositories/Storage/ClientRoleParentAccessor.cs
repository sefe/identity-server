// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

using IdentityServer.Data.Entities.Roles;

namespace IdentityServer.Data.Repositories.Storage;

internal class ClientRoleParentAccessor : IParentAccessor<ClientRoleMapping, ClientRole>
{
    public int GetParentEnvironmentId(ClientRole parent)
    {
        return parent.Client?.SystemPermissionEnvironmentId
            ?? throw new InvalidOperationException($"Bug: Application navigation property is not populated by the Entity Framework!");
    }

    public int GetParentId(ClientRoleMapping model)
    {
        return model.ClientRoleId;
    }
}
