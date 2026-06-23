// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

namespace IdentityServer.AdminPortal.Web.Services.Storage;

/// <summary>
/// Constants for identifying different storage service implementations when using keyed dependency injection
/// </summary>
public static class StorageServiceKeys
{
    /// <summary>
    /// Key for LocalStorage-based storage service
    /// </summary>
    public const string LocalStorage = "localStorage";
    
    /// <summary>
    /// Key for SessionStorage-based storage service
    /// </summary>
    public const string SessionStorage = "sessionStorage";
}
