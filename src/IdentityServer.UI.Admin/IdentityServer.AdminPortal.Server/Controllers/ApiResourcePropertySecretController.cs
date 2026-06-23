// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

using Microsoft.AspNetCore.Mvc;
using IdentityServer.Abstraction.Contracts;
using IdentityServer.Abstraction.DTO.ApiResources;

namespace IdentityServer.AdminPortal.Server.Controllers;

[Route("api/apiresource/secret")]
public class ApiResourcePropertySecretController : BasePropertyController<ApiResourcePropertySecretValueDtoRead, ApiResourcePropertySecretDtoCreate>
{
    public ApiResourcePropertySecretController(IDtoCreateRepository<ApiResourcePropertySecretValueDtoRead, ApiResourcePropertySecretDtoCreate> apiResourceSecretCreateRepository)
        : base(apiResourceSecretCreateRepository)
    {
    }
}
