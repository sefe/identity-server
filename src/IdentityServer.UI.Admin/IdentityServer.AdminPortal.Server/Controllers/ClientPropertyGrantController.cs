using Microsoft.AspNetCore.Mvc;
using IdentityServer.Abstraction.Contracts;
using IdentityServer.Abstraction.DTO.Clients;

namespace IdentityServer.AdminPortal.Server.Controllers;

[Route("api/client/grant")]
public class ClientPropertyGrantController : BasePropertyController<ClientPropertyGrantDtoRead, ClientPropertyGrantDtoCreate>
{
    public ClientPropertyGrantController(IDtoCreateRepository<ClientPropertyGrantDtoRead, ClientPropertyGrantDtoCreate> clientGrantCreateRepository)
        : base(clientGrantCreateRepository)
    {
    }
}
