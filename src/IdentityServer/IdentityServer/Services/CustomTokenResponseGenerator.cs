// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

using Duende.IdentityServer;
using Duende.IdentityServer.ResponseHandling;
using Duende.IdentityServer.Services;
using Duende.IdentityServer.Stores;
using Duende.IdentityServer.Validation;

namespace IdentityServer.Services;

public class CustomTokenResponseGenerator : TokenResponseGenerator
{
    public CustomTokenResponseGenerator(
        IClock clock,
        ITokenService tokenService,
        IRefreshTokenService refreshTokenService,
        IScopeParser scopeParser,
        IResourceStore resources,
        IClientStore clients,
        ILogger<CustomTokenResponseGenerator> logger)
        : base(clock, tokenService, refreshTokenService, scopeParser, resources, clients, logger)
    {
    }

    protected override Task<TokenResponse> ProcessTokenRequestAsync(TokenRequestValidationResult validationResult)
    {
        if (validationResult.CustomResponse != null &&
            validationResult.CustomResponse.TryGetValue(Abstraction.Constants.TokenExchange.AccessTokenLifetimeTemporaryClaimName, out var lifetimeObj) &&
            lifetimeObj is int lifetimeParsed
        )
        {
            validationResult.ValidatedRequest.AccessTokenLifetime = lifetimeParsed;
        }
        return base.ProcessTokenRequestAsync(validationResult);
    }
}
