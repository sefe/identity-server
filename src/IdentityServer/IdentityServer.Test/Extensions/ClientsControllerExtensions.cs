using Microsoft.AspNetCore.Mvc;
using IdentityServer.Abstraction.DTO.Clients;
using IdentityServer.Abstraction.Entities;
using IdentityServer.Controllers;

namespace IdentityServer.Test.Extensions;

internal static class ClientsControllerExtensions
{
    public static async Task<SearchResult<ClientDtoSearchResponse>> Call_SearchClientsAsync(this ClientsController controller, ClientDtoSearchRequest client)
    {
        var result = await controller.SearchClientsAsync(client);
        var entity = ((OkObjectResult)result.Result).Value as SearchResult<ClientDtoSearchResponse>;
        return entity!;
    }

    public static async Task<ClientDtoSearchResponse> Call_GetClientByClientIdAsync(this ClientsController controller, string clientId)
    {
        var result = await controller.GetClientByClientIdAsync(clientId);
        var entity = ((OkObjectResult)result.Result).Value as ClientDtoSearchResponse;
        return entity!;
    }
}
