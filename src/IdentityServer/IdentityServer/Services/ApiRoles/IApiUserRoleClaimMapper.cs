// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

using System.Security.Claims;

namespace IdentityServer.Services.ApiRoles;

public interface IApiUserRoleClaimMapper
{
    IAsyncEnumerable<Claim> ProcessApiRoleMappingsForUserAsync(IEnumerable<string> apiResourceNames, string userId);
}
