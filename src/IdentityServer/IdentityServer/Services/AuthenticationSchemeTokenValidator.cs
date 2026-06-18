using Duende.IdentityServer.Validation;
using Microsoft.AspNetCore.Authentication;

namespace IdentityServer.Services;

public class AuthenticationSchemeTokenValidator : ITokenValidator
{
    private readonly string _schemeName;
    private readonly IServiceProvider _serviceProvider;

    public AuthenticationSchemeTokenValidator(string schemeName, IServiceProvider serviceProvider)
    {
        _schemeName = schemeName;
        _serviceProvider = serviceProvider;
    }

    public async Task<TokenValidationResult> ValidateAccessTokenAsync(string token, string? expectedScope = null)
    {
        // Create a mock HTTP context to use the authentication handler
        var httpContext = new DefaultHttpContext
        {
            // Set the RequestServices to the application's service provider
            RequestServices = _serviceProvider
        };

        // Set the Authorization header with the token
        httpContext.Request.Headers.Authorization = $"Bearer {token}";

        // Authenticate using the specified scheme
        var result = await httpContext.AuthenticateAsync(_schemeName);

        if (!result.Succeeded)
        {
            return new TokenValidationResult
            {
                IsError = true,
                Error = $"Authentication scheme {_schemeName} rejected the token",
                ErrorDescription = result.Failure?.Message
            };
        }

        return new TokenValidationResult { IsError = false, Claims = result.Principal.Claims };
    }

    public Task<TokenValidationResult> ValidateIdentityTokenAsync(string token, string? clientId = null, bool validateLifetime = true)
    {
        throw new NotImplementedException();
    }
}

