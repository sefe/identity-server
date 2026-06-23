// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

namespace IdentityServer.AdminPortal.Web.Services.Storage;

public interface IJSStorageService
{
    Task<T?> GetItem<T>(string key);
    ValueTask RemoveItem(string key);
    ValueTask SetItem(string key, object data);
    ValueTask<string?> GetString(string key);
    ValueTask SetString(string key, string? value);
}
