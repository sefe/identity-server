// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

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
