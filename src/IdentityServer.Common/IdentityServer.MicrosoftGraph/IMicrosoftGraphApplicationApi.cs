// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

using IdentityServer.Abstraction.Entities.EntraEntities;

namespace IdentityServer.MicrosoftGraph;

public interface IMicrosoftGraphApplicationApi
{
    /// <summary>
    /// Retrieves an EntraID application by its application ID (don't mix for object ID).
    /// </summary>
    /// <param name="appId">The application ID of the application to retrieve. Cannot be null or empty.</param>
    /// <returns>A task that represents the asynchronous operation. The task result contains the <see cref="Application"/> object
    /// corresponding to the specified object ID, or <see langword="null"/> if no application is found.</returns>
    Task<Application?> GetApplicationByAppIdAsync(string appId);
}
