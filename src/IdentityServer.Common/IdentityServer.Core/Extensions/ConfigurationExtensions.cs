// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

using Microsoft.Extensions.Configuration;
using IdentityServer.Abstraction.Exceptions;

namespace IdentityServer.Core.Extensions;

public static class ConfigurationExtensions
{
    public static TSection DirectGetSection<TSection>(this IConfiguration configuration, string sectionName)
    {
        return configuration
                   .GetSection(sectionName)
                   .Get<TSection>()
               ?? throw new IdentityServerException($"Unable to retrieve the section '{sectionName}' from the configuration");
    }
}
