using Microsoft.AspNetCore.Mvc;
using IdentityServer.Abstraction.Contracts;
using IdentityServer.Abstraction.DTO.Clients;

namespace IdentityServer.AdminPortal.Server.Controllers;

[Route("api/client/secret")]
public class ClientPropertySecretController : BasePropertyController<ClientPropertySecretValueDtoRead, ClientPropertySecretDtoCreate>
{
    public ClientPropertySecretController(IDtoCreateRepository<ClientPropertySecretValueDtoRead, ClientPropertySecretDtoCreate> clientSecretCreateRepository)
        : base(clientSecretCreateRepository)
    {
    }
}
