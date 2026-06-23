// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

using System.IdentityModel.Tokens.Jwt;
using Duende.IdentityServer.Validation;

namespace IdentityServer.Services;

public class TokenValidatorSelector : ITokenValidatorSelector
{
    private readonly AuthSchemeIssuerMapping _authSchemeIssuerMapping;
    private readonly ILogger<TokenValidatorSelector> _logger;
    private readonly ITokenValidator _defaultValidator;
    private readonly IServiceProvider _serviceProvider;
    private readonly JwtSecurityTokenHandler _handler = new();

    public TokenValidatorSelector(
        ITokenValidator defaultValidator,
        AuthSchemeIssuerMapping authSchemeIssuerMapping,
        ILogger<TokenValidatorSelector> logger,
        IServiceProvider serviceProvider
        )
    {
        _defaultValidator = defaultValidator;
        _authSchemeIssuerMapping = authSchemeIssuerMapping;
        _logger = logger;
        _serviceProvider = serviceProvider;
    }

    public ITokenValidator SelectValidator(string token)
    {
        // Extract issuer from JWT
        try
        {
            string? issuer = null;

            var jwt = _handler.ReadJwtToken(token);
            issuer = jwt.Issuer;

            if (issuer != null && _authSchemeIssuerMapping.IssuerToSchemeMap.TryGetValue(issuer, out var scheme) && scheme != null)
            {
                return new AuthenticationSchemeTokenValidator(scheme, _serviceProvider);
            }
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "Failed to parse token as JWT");
        }

        return _defaultValidator;
    }
}
