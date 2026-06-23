// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

namespace IdentityServer.AdminPortal.Web.Services.Search;

public abstract class AdminApiProviderBase
{
    protected readonly IAdminApiService AdminApi;

    protected AdminApiProviderBase(IAdminApiService adminApi)
    {
        AdminApi = adminApi;
    }
}
