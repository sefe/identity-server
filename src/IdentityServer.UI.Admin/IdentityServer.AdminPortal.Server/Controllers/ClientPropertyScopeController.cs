using Microsoft.AspNetCore.Mvc;
using IdentityServer.Abstraction.Contracts;
using IdentityServer.Abstraction.DTO.Clients;

namespace IdentityServer.AdminPortal.Server.Controllers;

[Route("api/client/scope")]
public class ClientPropertyScopeController : BasePropertyController<ClientPropertyScopeDtoRead, ClientPropertyScopeDtoCreate>
{
    public ClientPropertyScopeController(IDtoCreateRepository<ClientPropertyScopeDtoRead, ClientPropertyScopeDtoCreate> clientScopeCreateRepository)
        : base(clientScopeCreateRepository)
    {
    }
}
