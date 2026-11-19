// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

namespace IdentityServer.Abstraction.Contracts;

/// <summary>
/// Invalidates authentication configuration affected by an administrative entity change.
/// Resource and scope changes invalidate the complete resource snapshot.
/// </summary>
public interface IConfigurationCacheInvalidator<T> where T : class
{
    Task RemoveAsync(string key);
}
