using Microsoft.AspNetCore.Mvc;
using IdentityServer.Abstraction.Contracts;
using IdentityServer.Abstraction.DTO.Clients;

namespace IdentityServer.AdminPortal.Server.Controllers;

[Route("api/client/cors")]
public class ClientPropertyCorsController : BasePropertyController<ClientPropertyCorsOriginDtoRead, ClientPropertyCorsOriginDtoCreate>
{
    public ClientPropertyCorsController(IDtoCreateRepository<ClientPropertyCorsOriginDtoRead, ClientPropertyCorsOriginDtoCreate> clientCorsCreateRepository)
        : base(clientCorsCreateRepository)
    {
    }
}
