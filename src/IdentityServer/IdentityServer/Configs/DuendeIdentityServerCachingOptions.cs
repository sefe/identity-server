// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

using Duende.IdentityServer.Configuration;
using IdentityServer.Abstraction.Configs;

namespace IdentityServer.Configs;

public class DuendeIdentityServerCachingOptions : IdentityServerCachingOptions
{
    public CachingOptions Duende { get; set; } = new();
}
