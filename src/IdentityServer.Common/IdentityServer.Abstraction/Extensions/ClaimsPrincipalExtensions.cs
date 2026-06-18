using System.Security.Claims;
using IdentityServer.Abstraction.Exceptions;
using static IdentityServer.Abstraction.Constants;

namespace IdentityServer.Abstraction.Extensions;

public static class ClaimsPrincipalExtensions
{
    public static string GetUserName(this ClaimsPrincipal user)
    {
        return user.Identity?.Name ?? user.FindFirst(ClaimNames.UserEmail)?.Value ??
            user.FindFirst(ClaimNames.UserOnPremisesSamAccountName)?.Value ?? GetUserObjectId(user);
    }

    public static string GetUserObjectId(this ClaimsPrincipal user)
    {
        return user.FindFirst(ClaimNames.UserObjectId)?.Value ??
            throw new UserClaimException(ClaimNames.UserObjectId, $"Mandatory claim '{ClaimNames.UserObjectId}' is missing");
    }

    public static string? GetUserNameOrDefault(this ClaimsPrincipal user)
    {
        return user.Identity?.Name
            ?? user.FindFirst(ClaimNames.UserEmail)?.Value
            ?? user.FindFirst(ClaimNames.UserOnPremisesSamAccountName)?.Value
            ?? user.FindFirst(ClaimNames.UserObjectId)?.Value;
    }

}
