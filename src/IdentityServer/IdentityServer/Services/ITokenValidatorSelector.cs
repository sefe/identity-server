using Duende.IdentityServer.Validation;

namespace IdentityServer.Services;

/// <summary>
/// Selects an ITokenValidator implementation for the provided token.
/// </summary>
public interface ITokenValidatorSelector
{
    ITokenValidator SelectValidator(string token);
}
