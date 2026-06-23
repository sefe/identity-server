// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

using Duende.IdentityModel;
using Duende.IdentityServer;
using Duende.IdentityServer.Configuration;
using Duende.IdentityServer.Models;
using Duende.IdentityServer.Services;
using Duende.IdentityServer.Stores;
using Microsoft.Extensions.Options;
using IdentityServer.Abstraction.Configs;
using static IdentityServer.Abstraction.Constants;

namespace IdentityServer.Services;

public class CustomLoggingTokenService : DefaultTokenService
{
    private readonly ILogger<CustomLoggingTokenService> _logger;
    private readonly CustomTokenLoggingSettings _loggingSettings;

    public CustomLoggingTokenService(
        IClock clock,
        IKeyMaterialService keys,
        IClaimsService claimsProvider,
        IReferenceTokenStore referenceTokenStore,
        ITokenCreationService creationService,
        ILogger<CustomLoggingTokenService> logger,
        IOptions<IdentityServerOptions> options,
        IOptions<CustomTokenLoggingSettings> loggingSettings)
        : base(claimsProvider, referenceTokenStore, creationService, clock, keys, options.Value, logger)
    {
        _logger = logger;
        _loggingSettings = loggingSettings.Value;
    }

    public override async Task<string> CreateSecurityTokenAsync(Token token)
    {
        var rawToken = await base.CreateSecurityTokenAsync(token);

        // Extract and log relevant information
        // Consider logging claims if necessary. Skipping them now to avoid excessive logging. 
        var subjectId = token.Claims?.FirstOrDefault(c => c.Type == ClaimNames.SubjectId);
        var displayName = token.Claims?.FirstOrDefault(c => c.Type == ClaimNames.UserDisplayName);
        var scopes = token.Scopes != null ? string.Join(", ", token.Scopes) : null;

        string tokenPreview = GetObfuscatedToken(token, rawToken);

        _logger.LogInformation(
            "Issued token: Type={TokenType}, AccessTokenType={AccessTokenType}, ClientId={ClientId}, SubjectId={SubjectId}, Display Name={DisplayName}, Scopes={Scopes}, TokenPreview={TokenPreview}",
            token.Type, token.AccessTokenType.ToString(), token.ClientId, subjectId?.Value, displayName?.Value, scopes, tokenPreview
        );

        return rawToken;
    }

    private string GetObfuscatedToken(Token token, string rawToken)
    {
        // Log at most last 16 chars for reference tokens
        if (token.Type == OidcConstants.TokenTypes.AccessToken && token.AccessTokenType == AccessTokenType.Reference)
        {
            var visibleLength = _loggingSettings.ReferenceTokenDefaultVisibleLength;
            var partialTokenLength = rawToken.Length > (visibleLength * 2) ? visibleLength : (rawToken.Length / 2);
            return string.Concat("***", rawToken.AsSpan(rawToken.Length - partialTokenLength));

        }
        else if (token.Type == OidcConstants.TokenTypes.AccessToken && token.AccessTokenType == AccessTokenType.Jwt)
        {
            // JWT: header.payload.signature
            var parts = rawToken.Split('.');
            var visibleParts = new List<string>();
            if ((_loggingSettings.JwtTokenVisibleParts & JwtTokenVisibleParts.Header) != 0 && parts.Length > 0)
            {
                visibleParts.Add(parts[0]);
            }
            if ((_loggingSettings.JwtTokenVisibleParts & JwtTokenVisibleParts.Payload) != 0 && parts.Length > 1)
            {
                visibleParts.Add(parts[1]);
            }
            return string.Join(".", visibleParts);
        }
        else
        {
            return string.Concat("***", rawToken.AsSpan(Math.Max(0, rawToken.Length - 4)));
        }
    }
}
