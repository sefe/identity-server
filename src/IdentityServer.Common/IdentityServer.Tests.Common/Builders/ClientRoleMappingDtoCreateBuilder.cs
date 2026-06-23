// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

using IdentityServer.Abstraction.DTO.Clients;
using IdentityServer.Abstraction.Entities.IdentityServerConfig;

namespace IdentityServer.Tests.Common.Builders;

public class ClientRoleMappingDtoCreateBuilder
{
    private readonly ClientPropertyRoleMappingDtoCreate _mapping;

    public ClientRoleMappingDtoCreateBuilder(ClientRoleMapType clientRoleMapping)
    {
        _mapping = new ClientPropertyRoleMappingDtoCreate
        {
             MappingType = clientRoleMapping
        };
    }

    public ClientRoleMappingDtoCreateBuilder WithClientId(int id)
    {
        _mapping.ClientId = id;
        return this;
    }

    public ClientRoleMappingDtoCreateBuilder WithClientRoleId(int id)
    {
        _mapping.ClientRoleId = id;
        return this;
    }

    public ClientPropertyRoleMappingDtoCreate Build()
    {
        return _mapping;
    }
}
