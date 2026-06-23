// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

using System.Security.Claims;

namespace IdentityServer.Services.ApiRoles;

public interface IApiClientRoleClaimMapper
{
    IAsyncEnumerable<Claim> ProcessApiRoleMappingsForClientIdAsync(IEnumerable<string> apiResourceNames, string clientId);
}
