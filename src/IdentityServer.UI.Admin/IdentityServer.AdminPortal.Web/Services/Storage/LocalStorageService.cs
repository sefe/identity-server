// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

using Microsoft.JSInterop;

namespace IdentityServer.AdminPortal.Web.Services.Storage;

public class LocalStorageService : BaseStorageService
{
    public LocalStorageService(IJSRuntime jsRuntime) : base(jsRuntime, "localStorage")
    {
    }
}
