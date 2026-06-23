// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

using Duende.IdentityServer.Configuration;
using Duende.IdentityServer.Models;
using Duende.IdentityServer.Validation;

namespace IdentityServer.Services.Validation;

/// <summary>
/// Allows clients with RequireClientSecret=false to use Client Credentials grant.
/// The implementation is taken from https://github.com/DuendeSoftware/products/blob/releases/is/7.3.x/identity-server/src/IdentityServer/Validation/Default/DefaultClientConfigurationValidator.cs#L246
/// </summary>
public class CustomClientConfigurationValidator : DefaultClientConfigurationValidator
{
    public CustomClientConfigurationValidator(IdentityServerOptions options) : base(options)
    {
    }

    protected override Task ValidateSecretsAsync(ClientConfigurationValidationContext context)
    {
        if (context.Client.AllowedGrantTypes?.Count > 0)
        {
            foreach (var grantType in context.Client.AllowedGrantTypes)
            {
                if (!string.Equals(grantType, GrantType.Implicit) && context.Client.RequireClientSecret && context.Client.ClientSecrets.Count == 0)
                {
                    context.SetError($"Client secret is required for {grantType}, but no client secret is configured.");
                    return Task.CompletedTask;
                }

                // This check is lifted: GrantType.ClientCredentials && !context.Client.RequireClientSecret
            }
        }

        return Task.CompletedTask;
    }
}
