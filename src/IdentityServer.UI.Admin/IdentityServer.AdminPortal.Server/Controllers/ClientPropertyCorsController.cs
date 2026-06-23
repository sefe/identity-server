// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

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
