// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

using Microsoft.AspNetCore.Mvc;
using System.Security.Claims;
using Telerik.DataSource;
using IdentityServer.Abstraction.DTO.Clients;
using IdentityServer.Abstraction.Entities.IdentityServerConfig;
using IdentityServer.AdminPortal.Server.Controllers;
using IdentityServer.AdminPortal.Test.Controller;
using IdentityServer.AdminPortal.Web.Models;

namespace IdentityServer.AdminPortal.Test.Extensions;

internal static class ClientControllerExtensions
{
    public static Func<int, ClientDtoCreate> GetDefaultClient => envId => GetDefaultClientWithGrant(envId, ClientGrantTypeNames.Grant_ClientCredentials);

    public static Func<int, string, ClientDtoCreate> GetDefaultClientWithGrant => (envId, grant) => new()
    {
        ClientId = Guid.NewGuid().ToString(),
        ClientName = "UnitClient1",
        SystemPermissionEnvironmentId = envId,
        AllowedGrantTypes = new HashSet<string> { grant }
    };

    public static async Task<ClientDtoRead> Call_CreateClientAsync(this ClientController controller, ClientDtoCreate client, ClaimsPrincipal user)
    {
        ControllerTestBase.SetControllerContext(controller, user);
        var result = await controller.CreateClientAsync(client);
        var entity = ((OkObjectResult)result.Result).Value as ClientDtoRead;
        return entity!;
    }

    public static async Task<ClientDtoRead> Call_CloneClientAsync(this ClientController controller, ClientDtoClone client, ClaimsPrincipal user)
    {
        ControllerTestBase.SetControllerContext(controller, user);
        var result = await controller.CloneClientAsync(client);
        var entity = ((OkObjectResult)result.Result).Value as ClientDtoRead;
        return entity!;
    }

    public static async Task<ClientDtoRead> Call_GetClientAsync(this ClientController controller, int clientId, ClaimsPrincipal user)
    {
        ControllerTestBase.SetControllerContext(controller, user);
        var result = await controller.GetClientByIdAsync(clientId);
        var entity = ((OkObjectResult)result.Result).Value as ClientDtoRead;
        return entity!;
    }

    public static async Task<List<ClientShortDtoRead>> Call_GetClientsPagedAsync(this ClientController controller, ClaimsPrincipal user)
    {
        var req = new DataSourceRequest()
        {
            Page = 1,
            PageSize = 10
        };
        ControllerTestBase.SetControllerContext(controller, user);
        var result = await controller.GetClientsPagedAsync(req);
        var entity = ((OkObjectResult)result.Result).Value as DataEnvelope<ClientShortDtoRead>;
        return entity!.CurrentPageData;
    }

    public static async Task<List<ClientShortDtoRead>> Call_GetClientsByScopePagedAsync(this ClientController controller, string scopeName, ClaimsPrincipal user)
    {
        var req = new DataSourceRequest()
        {
            Page = 1,
            PageSize = 10
        };
        ControllerTestBase.SetControllerContext(controller, user);
        var result = await controller.GetClientsByScopePagedAsync(scopeName, req);
        var entity = ((OkObjectResult)result.Result).Value as DataEnvelope<ClientShortDtoRead>;
        return entity!.CurrentPageData;
    }

    public static async Task<int?> Call_DeleteClientAsync(this ClientController controller, int clientId, ClaimsPrincipal user)
    {
        ControllerTestBase.SetControllerContext(controller, user);
        var result = await controller.DeleteClientByIdAsync(clientId);
        var entity = ((OkObjectResult)result.Result).Value as int?;
        return entity!;
    }

    public static async Task<ClientDtoRead> Call_UpdateClientAsync(this ClientController controller, ClientDtoUpdate client, ClaimsPrincipal user)
    {
        ControllerTestBase.SetControllerContext(controller, user);
        var result = await controller.UpdateClientAsync(client);
        var entity = ((OkObjectResult)result.Result).Value as ClientDtoRead;
        return entity!;
    }
}
