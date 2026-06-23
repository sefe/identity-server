// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

using System.Security.Claims;
using Duende.IdentityModel;
using Duende.IdentityServer;
using Duende.IdentityServer.Extensions;
using Duende.IdentityServer.Models;
using Duende.IdentityServer.Services;
using IdentityServer.Abstraction.Contracts.MicrosoftGraph;
using IdentityServer.Services.ApiRoles;
using IdentityServer.Services.ClientRoles;
using static IdentityServer.Abstraction.Constants;

namespace IdentityServer;

public class CustomProfileService : IProfileService
{
    private readonly IApiUserRoleClaimMapper _roleToClaimMapper;
    private readonly IClientUserRoleClaimMapper _clientRoleClaimMapper;
    private readonly IEntraUserService _userService;
    private readonly ILogger<CustomProfileService> _logger;

    public CustomProfileService(
        IApiUserRoleClaimMapper roleToClaimMapper,
        IClientUserRoleClaimMapper clientRoleClaimMapper,
        ILogger<CustomProfileService> logger,
        IEntraUserService userService)
    {
        _roleToClaimMapper = roleToClaimMapper;
        _clientRoleClaimMapper = clientRoleClaimMapper;
        _logger = logger;
        _userService = userService;
    }

    /// <inheritdoc/>
    public async Task GetProfileDataAsync(ProfileDataRequestContext context)
    {
        try
        {
            context.LogProfileRequest(_logger);
            context.AddRequestedClaims(context.Subject.Claims);

            var userObjectId = AddIssuedClaim(context, ClaimNames.UserObjectId);

            switch (context.Caller)
            {
                case IdentityServerConstants.ProfileDataCallers.ClaimsProviderAccessToken:
                    await HandleAccessTokenClaims(context, userObjectId);
                    HandleTokenExchangeClaims(context);
                    break;
                case IdentityServerConstants.ProfileDataCallers.ClaimsProviderIdentityToken:
                    await HandleIdTokenClaims(context, userObjectId);
                    break;
                case IdentityServerConstants.ProfileDataCallers.UserInfoEndpoint:
                    await AddUserInfoClaims(context, userObjectId);
                    break;
            }

            context.LogIssuedClaims(_logger);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "CustomProfileService failed");
        }
    }

    /// <inheritdoc/>
    public async Task IsActiveAsync(IsActiveContext context)
    {
        try
        {
            var userObjectId = context.Subject.FindFirst(ClaimNames.UserObjectId);
            if (userObjectId != null && !string.IsNullOrEmpty(userObjectId.Value))
            {
                var userResponse = await _userService.GetUserByObjectIdAsync(userObjectId.Value);
                context.IsActive = userResponse?.Users?.Any(u => u.OId == userObjectId.Value && u.AccountEnabled == true) == true;
            }
            else
            {
                context.IsActive = false;
            }
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to retrieve Entra user");
            context.IsActive = false;
        }
    }

    private static void HandleTokenExchangeClaims(ProfileDataRequestContext context)
    {
        if (context.Subject.GetAuthenticationMethod() != OidcConstants.GrantTypes.TokenExchange)
        {
            return;
        }

        // Add the actor claim if it exists in the subject claims
        var act = context.Subject.FindFirst(JwtClaimTypes.Actor);
        if (act != null)
        {
            context.IssuedClaims.Add(act);
        }
    }

    internal static Claim? AddIssuedClaim(ProfileDataRequestContext context, string claimName)
    {
        var claim = context.Subject?.FindFirst(claimName);
        if (claim != null)
        {
            context.IssuedClaims.Add(claim);
        }

        return claim;
    }

    internal static void AddNameIssuedClaim(ProfileDataRequestContext context)
    {
        if (!string.IsNullOrEmpty(context.Subject?.Identity?.Name))
        {
            context.IssuedClaims.Add(new Claim(ClaimNames.UserDisplayName, context.Subject.Identity.Name));
        }
    }

    internal async Task HandleAccessTokenClaims(ProfileDataRequestContext context, Claim? userObjectId)
    {
        if (context.RequestedResources.Resources.ApiResources.Count > 0)
        {
            await AddApiRoleClaims(context, userObjectId);
        }

        if (!string.IsNullOrEmpty(userObjectId?.Value))
        {
            await AddUserProperties(context, userObjectId);
        }

        AddIssuedClaim(context, ClaimNames.UserEmail);
        AddNameIssuedClaim(context);
    }

    internal async Task AddApiRoleClaims(ProfileDataRequestContext context, Claim? userObjectId)
    {
        if (string.IsNullOrEmpty(userObjectId?.Value))
        {
            _logger.LogWarning("Unable to load user groups because User ObjectId claim is missing");
            return;
        }

        var roleClaims = await _roleToClaimMapper.ProcessApiRoleMappingsForUserAsync(
            context.RequestedResources.Resources.ApiResources.Select(api => api.Name), userObjectId.Value).ToListAsync();
        context.IssuedClaims.AddRange(roleClaims);
    }

    internal async Task AddUserProperties(ProfileDataRequestContext context, Claim userObjectId)
    {
        var userProperties = await _userService.GetUserOnPremisePropertiesAsync(userObjectId.Value);
        foreach (var property in userProperties)
        {
            context.IssuedClaims.Add(new Claim(property.Key, property.Value));
        }
    }

    internal async Task AddUserInfoClaims(ProfileDataRequestContext context, Claim? userObjectId)
    {
        if (!string.IsNullOrEmpty(userObjectId?.Value))
        {
            var userProperties = await _userService.GetUserPropertiesAsync(userObjectId.Value);
            foreach (var property in userProperties.Where(p => !context.IssuedClaims.Any(c => string.Equals(c.Type, p.Key, StringComparison.OrdinalIgnoreCase))))
            {
                context.IssuedClaims.Add(new Claim(property.Key, property.Value));
            }
        }
    }

    internal async Task HandleIdTokenClaims(ProfileDataRequestContext context, Claim? userObjectId)
    {
        await AddClientRoleClaims(context, userObjectId);

        if (!string.IsNullOrEmpty(userObjectId?.Value))
        {
            await AddUserProperties(context, userObjectId);
        }

        AddIssuedClaim(context, ClaimNames.UserPrincipalName);
        AddNameIssuedClaim(context);
    }

    internal async Task AddClientRoleClaims(ProfileDataRequestContext context, Claim? userObjectId)
    {
        if (string.IsNullOrEmpty(userObjectId?.Value))
        {
            _logger.LogWarning("Unable to load user groups because User ObjectId claim is missing");
            return;
        }

        var roleClaims = await _clientRoleClaimMapper.ProcessClientRoleMappingsForUserAsync(
            context.Client.ClientId, userObjectId.Value).ToListAsync();
        context.IssuedClaims.AddRange(roleClaims);
    }
}
