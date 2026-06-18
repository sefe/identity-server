using Microsoft.AspNetCore.Mvc;
using IdentityServer.Abstraction.Contracts;
using IdentityServer.Abstraction.DTO.Clients;

namespace IdentityServer.AdminPortal.Server.Controllers;

[Route("api/client/role")]
public class ClientPropertyRoleController : BasePropertyController<ClientPropertyRoleDtoRead, ClientPropertyRoleDtoCreate>
{
    public ClientPropertyRoleController(IDtoCreateRepository<ClientPropertyRoleDtoRead, ClientPropertyRoleDtoCreate> clientRoleCreateRepository)
        : base(clientRoleCreateRepository)
    {
    }
}
