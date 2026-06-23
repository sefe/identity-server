// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

using Duende.IdentityServer.Configuration;

namespace IdentityServer.Configs;

public class CustomIdentityServerOptions
{
    public const string SectionName = "IdentityServer";

    public required DuendeIdentityServerCachingOptions CachingOptions { get; set; }

    public required AuthenticationOptions AuthenticationOptions { get; set; }
}
