// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

namespace IdentityServer.Services;

public class AuthSchemeIssuerMapping
{
    public Dictionary<string, string> IssuerToSchemeMap { get; } = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
}
