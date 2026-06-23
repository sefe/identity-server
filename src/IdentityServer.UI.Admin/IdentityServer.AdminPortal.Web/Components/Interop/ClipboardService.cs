// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

using Microsoft.JSInterop;

namespace IdentityServer.AdminPortal.Web.Components.Interop;

public class ClipboardService : IClipboardService
{
    private readonly IJSRuntime _jsInterop;

    public ClipboardService(IJSRuntime jsInterop)
    {
        _jsInterop = jsInterop;
    }

    public async Task CopyToClipboard(string text)
    {
        await _jsInterop.InvokeVoidAsync("navigator.clipboard.writeText", text);
    }
}
