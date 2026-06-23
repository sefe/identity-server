// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

using System.Security.Claims;
using IdentityServer.Abstraction.DTO.Clients;
using IdentityServer.AdminPortal.Server.Controllers;
using IdentityServer.AdminPortal.Test.Extensions;

namespace IdentityServer.AdminPortal.Test.Security;

public class ClientSecurityDtoTest : ItemSecurityDtoTestBase<ClientController, ClientDtoRead, ClientDtoCreate, ClientShortDtoRead>
{
    protected override Func<int, ClientDtoCreate> GetDefaultItem => ClientControllerExtensions.GetDefaultClient;

    protected override Task<ClientDtoRead> CreateFunc(ClientController controller, ClientDtoCreate item, ClaimsPrincipal user)
    {
        return controller.Call_CreateClientAsync(item, user);
    }
    protected override Task<List<ClientShortDtoRead>> GetAllFunc(ClientController controller, ClaimsPrincipal user)
    {
        return controller.Call_GetClientsPagedAsync(user);
    }
    protected override Task<ClientDtoRead> GetFunc(ClientController controller, int id, ClaimsPrincipal user)
    {
        return controller.Call_GetClientAsync(id, user);
    }
    protected override Task<ClientDtoRead> UpdateFunc(ClientController controller, int id, ClaimsPrincipal user)
    {
        var item = new ClientDtoUpdate
        {
            Id = id,
            Description = "Updated description",
        };
        return controller.Call_UpdateClientAsync(item, user);
    }
    protected override Task<int?> DeleteFunc(ClientController controller, int id, ClaimsPrincipal user)
    {
        return controller.Call_DeleteClientAsync(id, user);
    }

    protected override Task<ClientDtoRead> CloneFunc(ClientController controller, int id, int targetEnvId, ClaimsPrincipal user)
    {
        var item = new ClientDtoClone
        {
            Id = id,
            ClientId = Guid.NewGuid().ToString(),
            ClientName = "Cloned Client",
            SystemPermissionEnvironmentId = targetEnvId
        };
        return controller.Call_CloneClientAsync(item, user);
    }
}
