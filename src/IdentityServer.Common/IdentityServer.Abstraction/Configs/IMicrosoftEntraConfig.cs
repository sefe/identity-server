// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

namespace IdentityServer.Abstraction.Configs;

public interface IMicrosoftEntraConfig
{
    string ClientId { get; }
    string TenantId { get; }
    string ClientSecret { get; }
}
