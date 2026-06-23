// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

using Microsoft.JSInterop;

namespace IdentityServer.AdminPortal.Web.Services.Storage;

public class SessionStorageService : BaseStorageService
{
    public SessionStorageService(IJSRuntime jsRuntime) : base(jsRuntime, "sessionStorage")
    {
    }
}
