// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

using IdentityServer.Abstraction.Entities.EntraEntities;

namespace IdentityServer.Abstraction.Contracts.MicrosoftGraph;

public interface IEntraApplicationService
{
    Task<Application?> GetByIdAsync(string appId);
}
