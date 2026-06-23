// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

using System.Security.Claims;
using System.Text.Json;
using Microsoft.AspNetCore.Components.WebAssembly.Authentication;
using Microsoft.AspNetCore.Components.WebAssembly.Authentication.Internal;

namespace IdentityServer.AdminPortal.Web.Services;

public class ExtendedUserAccountFactory : AccountClaimsPrincipalFactory<RemoteUserAccount>
{
    private readonly UserRoleFilteringService _roleFilteringService;

    public ExtendedUserAccountFactory(IAccessTokenProviderAccessor accessor, UserRoleFilteringService roleFilteringService) : base(accessor)
    {
        _roleFilteringService = roleFilteringService;
    }

    public override async ValueTask<ClaimsPrincipal> CreateUserAsync(RemoteUserAccount account, RemoteAuthenticationUserOptions options)
    {
        var initialUser = await base.CreateUserAsync(account, options);

        if (initialUser.Identity is ClaimsIdentity userIdentity && initialUser.Identity.IsAuthenticated)
        {
            var accessTokenResult = await TokenProvider.RequestAccessToken();
            if (accessTokenResult.TryGetToken(out var accessToken))
            {
                var claims = GetAccessTokenClaims(accessToken.Value);
                if (claims.TryGetValue("role", out var claimObject))
                {
                    var allowedRoles = await _roleFilteringService.GetAllowedRoles();
                    AddRoleClaimObject(userIdentity, claimObject, allowedRoles);
                }
            }
        }

        return initialUser;
    }

    private static void AddRoleClaimObject(ClaimsIdentity userIdentity, object claimObj, List<string> allowedRoles)
    {
        try
        {
            foreach (var arElement in ((JsonElement)claimObj).EnumerateArray())
            {
                AddRoleClaim(userIdentity, arElement.GetString(), allowedRoles);
            }
        }
        catch
        {
            AddRoleClaim(userIdentity, claimObj.ToString(), allowedRoles);
        }
    }

    private static void AddRoleClaim(ClaimsIdentity userIdentity, string? value, List<string> allowedRoles)
    {
        if (!string.IsNullOrEmpty(value) && allowedRoles.Contains(value))
        {
            userIdentity.AddClaim(new Claim("role", value));
        }
    }

    protected static IDictionary<string, object> GetAccessTokenClaims(string accessToken)
    {
        if (string.IsNullOrEmpty(accessToken))
        {
            return new Dictionary<string, object>();
        }

        // header.payload.signature
        var payload = accessToken.Split(".")[1];
        var base64Payload = payload.Replace('-', '+').Replace('_', '/')
            .PadRight(payload.Length + (4 - payload.Length % 4) % 4, '=');

        return JsonSerializer.Deserialize<IDictionary<string, object>>(
            Convert.FromBase64String(base64Payload)) ?? new Dictionary<string, object>();
    }
}
