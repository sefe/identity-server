using Microsoft.AspNetCore.Mvc;
using IdentityServer.Abstraction.Contracts;
using IdentityServer.Abstraction.DTO.Clients;

namespace IdentityServer.AdminPortal.Server.Controllers;

[Route("api/client/rolemapping")]
public class ClientPropertyRoleMappingController : BasePropertyController<ClientPropertyRoleMappingDtoRead, ClientPropertyRoleMappingDtoCreate>
{
    public ClientPropertyRoleMappingController(IDtoCreateRepository<ClientPropertyRoleMappingDtoRead, ClientPropertyRoleMappingDtoCreate> clientRoleMappingCreateRepository)
        : base(clientRoleMappingCreateRepository)
    {
    }
}
