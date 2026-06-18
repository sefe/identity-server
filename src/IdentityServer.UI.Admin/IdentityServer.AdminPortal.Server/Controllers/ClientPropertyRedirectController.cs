using Microsoft.AspNetCore.Mvc;
using IdentityServer.Abstraction.Contracts;
using IdentityServer.Abstraction.DTO.Clients;

namespace IdentityServer.AdminPortal.Server.Controllers;

[Route("api/client/redirect")]
public class ClientPropertyRedirectController : BasePropertyController<ClientPropertyRedirectUriDtoRead, ClientPropertyRedirectUriDtoCreate>
{
    public ClientPropertyRedirectController(IDtoCreateRepository<ClientPropertyRedirectUriDtoRead, ClientPropertyRedirectUriDtoCreate> clientRedirectCreateRepository)
        : base(clientRedirectCreateRepository)
    {
    }
}
