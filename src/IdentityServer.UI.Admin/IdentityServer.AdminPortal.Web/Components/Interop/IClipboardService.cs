// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

namespace IdentityServer.AdminPortal.Web.Components.Interop;

public interface IClipboardService
{
    Task CopyToClipboard(string text);
}
