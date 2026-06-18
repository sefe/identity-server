using Microsoft.AspNetCore.Mvc;
using IdentityServer.Abstraction.Contracts;
using IdentityServer.Abstraction.DTO.Clients;

namespace IdentityServer.AdminPortal.Server.Controllers;

[Route("api/client/entraapp")]
public class ClientPropertyEntraAppController : BasePropertyController<ClientPropertyEntraAppDtoRead, ClientPropertyEntraAppDtoCreate>
{
    public ClientPropertyEntraAppController(IDtoCreateRepository<ClientPropertyEntraAppDtoRead, ClientPropertyEntraAppDtoCreate> clientEntraAppCreateRepository)
        : base(clientEntraAppCreateRepository)
    {
    }
}
