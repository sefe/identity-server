// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

using System.Security.Claims;
using Duende.IdentityServer.Validation;
using IdentityServer.Abstraction.Entities.IdentityServerConfig;

namespace IdentityServer.Services.ApiRoles;

/// <summary>
/// Adds M2M claim and maps API roles to claims for client credentials grant type.
/// </summary>
public class ApiClientCredentialsRoleMapper : ICustomTokenRequestValidator
{
    private readonly IApiClientRoleClaimMapper _roleToClaimMapper;
    private readonly ILogger<ApiClientCredentialsRoleMapper> _logger;

    public ApiClientCredentialsRoleMapper(
        IApiClientRoleClaimMapper roleToClaimMapper,
        ILogger<ApiClientCredentialsRoleMapper> logger)
    {
        _roleToClaimMapper = roleToClaimMapper;
        _logger = logger;
    }

    public async Task ValidateAsync(CustomTokenRequestValidationContext context)
    {
        if (context.Result?.ValidatedRequest.GrantType != ClientGrantTypeNames.Grant_ClientCredentials)
        {
            return;
        }

        context.Result.ValidatedRequest.ClientClaims.Add(new Claim(Abstraction.Constants.ClaimNames.M2M, bool.TrueString));
        var clientId = context.Result.ValidatedRequest.ClientId;
        _logger.LogDebug("Processing custom role mapping for Client ID '{ClientId}' grant 'client_credentials'", clientId);

        var roleClaims = await _roleToClaimMapper.ProcessApiRoleMappingsForClientIdAsync(
            context.Result.ValidatedRequest.ValidatedResources.Resources.ApiResources.Select(api => api.Name), clientId).ToListAsync();
        foreach (var rc in roleClaims.Where(rc => rc != null))
        {
            context.Result.ValidatedRequest.ClientClaims.Add(rc);
        }
    }
}
