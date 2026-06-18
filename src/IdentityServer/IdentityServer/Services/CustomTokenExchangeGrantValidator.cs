using System.Security.Claims;
using System.Text.Json;
using System.Text.Json.Serialization;
using Duende.IdentityModel;
using Duende.IdentityServer;
using Duende.IdentityServer.Models;
using Duende.IdentityServer.Validation;
using IdentityServer.Abstraction.Contracts;
using IdentityServer.Abstraction.Entities.IdentityServerConfig;
using IdentityServer.Data.DuendeEntityExtensions;

namespace IdentityServer.Services;

public class CustomTokenExchangeGrantValidator : IExtensionGrantValidator
{
    private readonly ILogger<CustomTokenExchangeGrantValidator> _logger;
    private readonly ITokenValidatorSelector _validatorSelector;
    private readonly ISecretsListValidator _clientSecretValidator;
    private readonly IStorage<ClientExt> _clientStorage;

    public CustomTokenExchangeGrantValidator(
        ITokenValidatorSelector validatorSelector,
        ISecretsListValidator clientSecretValidator,
        IStorage<ClientExt> clientStorage,
        ILogger<CustomTokenExchangeGrantValidator> logger)
    {
        _validatorSelector = validatorSelector;
        _clientSecretValidator = clientSecretValidator;
        _clientStorage = clientStorage;
        _logger = logger;
    }

    public string GrantType => ClientGrantTypeNames.Grant_TokenExchange;

    public async Task ValidateAsync(ExtensionGrantValidationContext context)
    {
        _logger.LogInformation("ValidateAsync called with GrantType: {GrantType}", GrantType);

        var subjectToken = ExtractAndValidateParameters(context);
        if (!string.IsNullOrEmpty(context.Result.ErrorDescription))
        {
            return;
        }

        // --- ACTOR TOKEN PROCESSING (RFC8693) ---
        Claim? actorClaim = await ProcessActorToken(context);
        if (!string.IsNullOrEmpty(context.Result.ErrorDescription))
        {
            // Error already set in context by actor token processing
            return;
        }
        // --- END ACTOR TOKEN PROCESSING ---

        bool isRequestAuthenticated = await EnsureRequestAuthentication(context, actorClaim);
        if (!isRequestAuthenticated)
        {
            // Error already set in context by EnsureRequestAuthentication
            return;
        }

        var subjectTokenResult = await ValidateSubjectTokenAsync(subjectToken, context);
        if (!string.IsNullOrEmpty(context.Result.ErrorDescription))
        {
            return;
        }

        var subjectUserObjectId = ExtractUserObjectIds(subjectTokenResult, context);
        if (!string.IsNullOrEmpty(context.Result.ErrorDescription))
        {
            return;
        }

        var subjectClientId = ExtractClientIds(subjectTokenResult, context);
        if (!string.IsNullOrEmpty(context.Result.ErrorDescription))
        {
            return;
        }

        await ValidateIssuerSpecificClaims(subjectTokenResult, context, subjectClientId);
        if (!string.IsNullOrEmpty(context.Result.ErrorDescription))
        {
            return;
        }

        int reducedAccessTokenLifetime = CalculateAccessTokenLifetime(subjectTokenResult, context);
        if (!string.IsNullOrEmpty(context.Result.ErrorDescription))
        {
            return;
        }

        context.Request.ClientId = subjectClientId; // Preserve the clientId from the subject token for the response
        var claims = BuildClaims(subjectTokenResult, actorClaim);

        _logger.LogInformation("Token exchange successful for userObjectId: {UserObjectId}, clientId: {SubjectClientId}", subjectUserObjectId, subjectClientId);

        context.Result = new GrantValidationResult(
            identityProvider: Abstraction.Constants.TokenExchange.IdentityProvider,
            subject: subjectUserObjectId,
            authenticationMethod: GrantType,
            authTime: ExtractAuthDateTime(subjectTokenResult),
            claims: claims,
            customResponse: CreateCustomResponse(reducedAccessTokenLifetime));
    }

    private async Task<bool> EnsureRequestAuthentication(ExtensionGrantValidationContext context, Claim? actorClaim)
    {
        // the token exchange reqquest must be authenticated either by client authentication or by actor token
        bool isAuthenticated = false;
        if (actorClaim != null)
        {
            isAuthenticated = true; // Actor token is present, no need for client authentication
            _logger.LogInformation("Request was authenticated by the Actor token");
        }
        else if (context.Request.Client != null && context.Request.Secret != null)
        {
            var secretValidationResult = await _clientSecretValidator.ValidateAsync(context.Request.Client.ClientSecrets, context.Request.Secret);
            if (secretValidationResult?.Success == true)
            {
                isAuthenticated = true; // Client authentication succeeded
                _logger.LogInformation("Request was authenticated by the Client Secret");
            }
        }

        if (!isAuthenticated)
        {
            _logger.LogWarning("Actor token or Client Credentials authentication is required for token exchange grant");
            context.Result = new GrantValidationResult(TokenRequestErrors.InvalidClient, "Actor token or Client Credentials authentication is required for token exchange grant");
            return false;
        }

        return true;
    }

    internal string ExtractAndValidateActorTokenParameters(ExtensionGrantValidationContext context)
    {
        _logger.LogDebug("ExtractAndValidateActorTokenParameters called");
        var actorToken = context.Request.Raw.Get(Abstraction.Constants.TokenExchange.ActorToken);
        var actorTokenType = context.Request.Raw.Get(Abstraction.Constants.TokenExchange.ActorTokenType);
        _logger.LogDebug("actorToken: {ActorToken}, actorTokenType: {ActorTokenType}", actorToken, actorTokenType);
        if (string.IsNullOrEmpty(actorToken))
        {
            _logger.LogDebug("No actor_token provided");
            return string.Empty;
        }

        if (string.IsNullOrEmpty(actorTokenType) || actorTokenType != Abstraction.Constants.TokenTypes.AccessToken)
        {
            _logger.LogWarning("Invalid actor_token_type '{SubjectTokenType}', must be '{ExpectedSubjectTokenType}'", actorTokenType, Abstraction.Constants.TokenTypes.AccessToken);
            context.Result = new GrantValidationResult(TokenRequestErrors.InvalidRequest, $"actor_token_type must be '{Abstraction.Constants.TokenTypes.AccessToken}'");
            return string.Empty;
        }

        _logger.LogDebug("Extracted actor_token");

        if (actorToken.Length > Abstraction.Constants.TokenExchange.MaxActorTokenLength)
        {
            _logger.LogWarning("actor_token exceeds maximum length of {MaxLength} characters", Abstraction.Constants.TokenExchange.MaxActorTokenLength);
            context.Result = new GrantValidationResult(TokenRequestErrors.InvalidRequest, $"actor_token exceeds maximum length of {Abstraction.Constants.TokenExchange.MaxActorTokenLength} characters");
            return string.Empty;
        }
        _logger.LogDebug("ExtractAndValidateActorTokenParameters succeeded");
        return actorToken;
    }

    internal async Task<TokenValidationResult?> ValidateActorTokenAsync(string actorToken, ExtensionGrantValidationContext context)
    {
        _logger.LogDebug("ValidateActorTokenAsync called with actorToken length: {Length}", actorToken.Length);
        var actorValidator = _validatorSelector.SelectValidator(actorToken);
        var actorValidationResult = await actorValidator.ValidateAccessTokenAsync(actorToken);
        if (actorValidationResult.IsError)
        {
            _logger.LogWarning("actor_token validation failed: {Error}", actorValidationResult.Error);
            context.Result = new GrantValidationResult(TokenRequestErrors.InvalidRequest, $"actor_token validation failed: {actorValidationResult.Error}");
            return null;
        }
        else if (actorValidationResult.Claims?.Any() != true)
        {
            _logger.LogWarning("actor_token contains no claims");
            context.Result = new GrantValidationResult(TokenRequestErrors.InvalidRequest, "actor_token contains no claims");
            return null;
        }
        _logger.LogDebug("ValidateActorTokenAsync succeeded");
        return actorValidationResult;
    }

    internal async Task<Claim?> ProcessActorToken(ExtensionGrantValidationContext context)
    {
        _logger.LogDebug("ProcessActorToken called");
        var actorToken = ExtractAndValidateActorTokenParameters(context);
        if (string.IsNullOrEmpty(actorToken))
        {
            _logger.LogDebug("No valid actor_token to process");
            return null;
        }
        var actorValidationResult = await ValidateActorTokenAsync(actorToken, context);
        if (actorValidationResult == null)
        {
            _logger.LogDebug("Actor token validation failed");
            return null;
        }

        // the clientId must be the same as in the actor token
        if (!string.Equals(actorValidationResult.Claims?.FirstOrDefault(c => c.Type == JwtClaimTypes.ClientId)?.Value, context.Request.Client.ClientId, StringComparison.Ordinal)) // exact match required
        {
            _logger.LogWarning("Client Ids must be the same in the token request and the Actor token ClientId claim");
            context.Result = new GrantValidationResult(TokenRequestErrors.InvalidClient, "Client Ids must be the same in the token request and the Actor token ClientId claim");
            return null;
        }

        var claim = BuildActorClaim(actorValidationResult, context);
        _logger.LogDebug("ProcessActorToken succeeded");
        return claim;
    }

    /// <summary>
    /// Use reduced access token lifetime based on the subject token's expiration time to avoid infinite token refresh via token exchange grant.
    /// </summary>
    /// <param name="validationResult">Validation Result</param>
    /// <returns>Reduced Access Token lifetime</returns>
    internal int CalculateAccessTokenLifetime(TokenValidationResult validationResult, ExtensionGrantValidationContext context)
    {
        _logger.LogDebug("CalculateAccessTokenLifetime called");
        var subjectTokenExpiresAt = ExtractExpiresDateTime(validationResult, context);
        if (!string.IsNullOrEmpty(context.Result.ErrorDescription))
        {
            _logger.LogWarning("ExtractExpiresDateTime failed: {Error}", context.Result.ErrorDescription);
            return 0;
        }

        if (subjectTokenExpiresAt == DateTime.MinValue)
        {
            _logger.LogWarning("ExtractExpiresDateTime returned an invalid date");
            context.Result = new GrantValidationResult(TokenRequestErrors.InvalidRequest, "subject_token expiration is invalid");
            return 0; // Invalid date, cannot proceed
        }
        _logger.LogDebug("Extracted subject_token expiration: {SubjectTokenExpiresAt}", subjectTokenExpiresAt);

        int reducedLifetime = (int)(subjectTokenExpiresAt - DateTime.UtcNow).TotalSeconds;
        if (reducedLifetime <= 0)
        {
            _logger.LogWarning("subject_token expiration is invalid: {SubjectTokenExpiresAt}", subjectTokenExpiresAt);
            context.Result = new GrantValidationResult(TokenRequestErrors.InvalidRequest, "subject_token expiration is invalid");
            return 0;
        }
        else if (reducedLifetime > Abstraction.Constants.TokenExchange.MaxAccessTokenLifetimeSeconds)
        {
            _logger.LogWarning("subject_token expiration exceeded {MaxTokenValidityCap} cap by {TokenValidityDiff}",
                Abstraction.Constants.TokenExchange.MaxAccessTokenLifetimeSeconds,
                reducedLifetime - Abstraction.Constants.TokenExchange.MaxAccessTokenLifetimeSeconds);
            reducedLifetime = Abstraction.Constants.TokenExchange.MaxAccessTokenLifetimeSeconds; // Cap to max lifetime
        }

        _logger.LogDebug("CalculateAccessTokenLifetime returning: {Lifetime}", reducedLifetime);
        return reducedLifetime;
    }

    internal DateTime ExtractExpiresDateTime(TokenValidationResult validationResult, ExtensionGrantValidationContext context)
    {
        _logger.LogDebug("ExtractExpiresDateTime called");
        long expiresUnix = 0;
        var hasExpiration = validationResult?.Claims?
            .FirstOrDefault(c => c.Type == JwtClaimTypes.Expiration)?
            .Value is string expStr && long.TryParse(expStr, out expiresUnix);

        if (!hasExpiration)
        {
            _logger.LogWarning("subject_token is missing expiration claim");
            context.Result = new GrantValidationResult(TokenRequestErrors.InvalidRequest, "subject_token is missing expiration claim");
            return DateTime.MinValue; // Return min date to avoid further processing
        }
        if (expiresUnix <= 0)
        {
            _logger.LogWarning("subject_token expiration is invalid: {ExpiresUnix}", expiresUnix);
            context.Result = new GrantValidationResult(TokenRequestErrors.InvalidRequest, "subject_token expiration is invalid");
            return DateTime.MinValue; // Return min date to avoid further processing
        }

        _logger.LogDebug("Extracted subject_token expiration: {ExpiresUnix}", expiresUnix);
        var expiresAt = DateTimeOffset.FromUnixTimeSeconds(expiresUnix).UtcDateTime;
        _logger.LogDebug("ExtractExpiresDateTime returning: {ExpiresAt}", expiresAt);
        return expiresAt;
    }

    internal static DateTime ExtractAuthDateTime(TokenValidationResult validationResult)
    {
        return validationResult?.Claims?
            .FirstOrDefault(c => c.Type == JwtClaimTypes.AuthenticationTime)?
            .Value is string authTimeStr && long.TryParse(authTimeStr, out var authTime)
            ? DateTimeOffset.FromUnixTimeSeconds(authTime).UtcDateTime
            : DateTime.UtcNow;
    }

    internal static Dictionary<string, object> CreateCustomResponse(int accessTokenLifetime)
    {
        return new Dictionary<string, object>
        {
            {OidcConstants.TokenResponse.IssuedTokenType, OidcConstants.TokenTypeIdentifiers.AccessToken},
            {Abstraction.Constants.TokenExchange.AccessTokenLifetimeTemporaryClaimName, accessTokenLifetime}
        };
    }

    internal string ExtractAndValidateParameters(ExtensionGrantValidationContext context)
    {
        _logger.LogDebug("ExtractAndValidateParameters called");
        var subjectTokenType = context.Request.Raw.Get(Abstraction.Constants.TokenExchange.SubjectTokenType);
        var subjectToken = context.Request.Raw.Get(Abstraction.Constants.TokenExchange.SubjectToken);
        _logger.LogDebug("subjectTokenType: {SubjectTokenType}, subjectToken length: {Length}", subjectTokenType, subjectToken?.Length);

        if (subjectTokenType != Abstraction.Constants.TokenTypes.AccessToken)
        {
            _logger.LogWarning("Invalid subject_token_type '{SubjectTokenType}', must be '{ExpectedSubjectTokenType}'", subjectTokenType, Abstraction.Constants.TokenTypes.AccessToken);
            context.Result = new GrantValidationResult(TokenRequestErrors.InvalidRequest, $"subject_token_type must be '{Abstraction.Constants.TokenTypes.AccessToken}'");
            return string.Empty;
        }

        if (string.IsNullOrEmpty(subjectToken))
        {
            _logger.LogWarning("subject_token is missing");
            context.Result = new GrantValidationResult(TokenRequestErrors.InvalidRequest, "subject_token is missing");
            return string.Empty;
        }

        if (subjectToken.Length > Abstraction.Constants.TokenExchange.MaxSubjectTokenLength)
        {
            _logger.LogWarning("subject_token exceeds maximum length of {MaxLength} characters", Abstraction.Constants.TokenExchange.MaxSubjectTokenLength);
            context.Result = new GrantValidationResult(TokenRequestErrors.InvalidRequest, $"subject_token exceeds maximum length of {Abstraction.Constants.TokenExchange.MaxSubjectTokenLength} characters");
            return string.Empty;
        }
        else
        {
            _logger.LogDebug("ExtractAndValidateParameters succeeded");
            return subjectToken;
        }
    }

    internal async Task<TokenValidationResult> ValidateSubjectTokenAsync(string subjectToken, ExtensionGrantValidationContext context)
    {
        _logger.LogDebug("ValidateSubjectTokenAsync called with subjectToken length: {Length}", subjectToken.Length);
        var validator = _validatorSelector.SelectValidator(subjectToken);
        var validationResult = await validator.ValidateAccessTokenAsync(subjectToken);
        if (validationResult.IsError)
        {
            _logger.LogWarning("subject_token validation failed: {Error}", validationResult.Error);
            context.Result = new GrantValidationResult(TokenRequestErrors.InvalidRequest, $"subject_token validation failed: {validationResult.Error}");
        }
        else if (validationResult.Claims?.Any() != true)
        {
            _logger.LogWarning("subject_token contains no claims");
            context.Result = new GrantValidationResult(TokenRequestErrors.InvalidRequest, "subject_token contains no claims");
        }
        _logger.LogDebug("ValidateSubjectTokenAsync succeeded");
        return validationResult;
    }

    /// <summary>
    /// Applies issuer-specific validation for the subject token.
    /// For Entra issuer validate the required scope to protect against "empty" tokens.
    /// For DIS issuer ensure the audience matches the clientId in the token request to protect against clientId forgery.
    /// </summary>
    /// <param name="validationResult">Validation Result</param>
    /// <param name="context">Validation Context</param>
    internal async Task ValidateIssuerSpecificClaims(TokenValidationResult validationResult, ExtensionGrantValidationContext context, string subjectClientId)
    {
        _logger.LogDebug("ValidateIssuerSpecificClaims called");
        var issuer = validationResult.Claims?.FirstOrDefault(c => c.Type == JwtClaimTypes.Issuer)?.Value;
        if (string.IsNullOrEmpty(issuer))
        {
            _logger.LogWarning("subject_token is missing issuer claim");
            context.Result = new GrantValidationResult(TokenRequestErrors.InvalidRequest, "subject_token is missing issuer claim");
            return;
        }
        _logger.LogDebug("Issuer: {Issuer}", issuer);

        // Check issuer claim for EntraID
        if (IsEntraIdIssuer(issuer))
        {
            _logger.LogDebug("subject_token issuer is EntraID");
            if (!ValidateEntraIdTokenExchangeScope(validationResult, context) || !await ValidateEntraIdAppIsConfigured(context, subjectClientId))
            {
                return;
            }
        }
        else if (IsIdentityServerIssuer(issuer))
        {
            _logger.LogDebug("subject_token issuer is IdentityServer");
            var subjectAudience = validationResult.Claims?.FirstOrDefault(c => c.Type == JwtClaimTypes.Audience)?.Value;
            if (string.IsNullOrEmpty(subjectAudience))
            {
                _logger.LogWarning("subject_token issued by IdentityServer contains no audience claim");
                context.Result = new GrantValidationResult(TokenRequestErrors.InvalidRequest, "subject_token issued by IdentityServer contains no audience claim");
                return;
            }
            // Within the same IDP the subject token audience must be equal to the clientId in the token request
            if (!string.Equals(subjectAudience, context.Request.Client.ClientId, StringComparison.Ordinal)) // exact match required
            {
                _logger.LogWarning("Client Id in the token request '{RequestClientId}' mismatches the DIS subject token audience claim '{SubjectAudience}'", context.Request.Client.ClientId, subjectAudience);
                context.Result = new GrantValidationResult(TokenRequestErrors.InvalidClient, $"Client Id in the token request '{context.Request.Client.ClientId}' mismatches the DIS subject token audience claim '{subjectAudience}'");
                return;
            }
        }
        else
        {
            _logger.LogWarning("Unrecognized subject_token issuer '{Issuer}'", issuer);
            context.Result = new GrantValidationResult(TokenRequestErrors.InvalidRequest, $"Unrecognized subject_token issuer '{issuer}'");
            return;
        }
        _logger.LogDebug("ValidateIssuerSpecificClaims completed");
    }

    internal bool ValidateEntraIdTokenExchangeScope(TokenValidationResult validationResult, ExtensionGrantValidationContext context)
    {
        var scopes = validationResult.Claims?.FirstOrDefault(c => c.Type == Abstraction.Constants.ClaimNamesEntra.Scope)?.Value;
        if (string.IsNullOrEmpty(scopes))
        {
            _logger.LogWarning("subject_token issued by EntraID contains no scopes");
            context.Result = new GrantValidationResult(TokenRequestErrors.InvalidRequest, "subject_token issued by EntraID contains no scopes");
            return false;
        }

        var scopeList = scopes.Split(Abstraction.Constants.TokenExchange.ScopeSeparator, StringSplitOptions.RemoveEmptyEntries);
        if (!scopeList.Contains(Abstraction.Constants.ScopeNamesEntra.IdentityServerTokenExchangeScope))
        {
            _logger.LogWarning("subject_token issued by EntraID does not contain required scope: {RequiredScope}", Abstraction.Constants.ScopeNamesEntra.IdentityServerTokenExchangeScope);
            context.Result = new GrantValidationResult(TokenRequestErrors.InvalidRequest, $"subject_token issued by EntraID does not contain required scope '{Abstraction.Constants.ScopeNamesEntra.IdentityServerTokenExchangeScope}'");
            return false;
        }

        return true;
    }

    internal async Task<bool> ValidateEntraIdAppIsConfigured(ExtensionGrantValidationContext context, string subjectClientId)
    {
        var clientHasConfiguredEntraApp = await _clientStorage.AnyAsync(c => c.ClientId == context.Request.Client.ClientId && c.EntraApps.Any(cea => cea.AppId == subjectClientId));
        if (!clientHasConfiguredEntraApp)
        {
            _logger.LogWarning("EntraID application '{SubjectClientId}' is not allowed to perform Token Exchange flow via client '{ClientId}'", subjectClientId, context.Request.Client.ClientId);
            context.Result = new GrantValidationResult(TokenRequestErrors.InvalidRequest, $"EntraID application '{subjectClientId}' is not allowed to perform Token Exchange flow via client '{context.Request.Client.ClientId}'");
            return false;
        }
        return true;
    }

    internal static bool IsEntraIdIssuer(string issuer)
    {
        return issuer.StartsWith("https://sts.windows.net/", StringComparison.Ordinal) || issuer.StartsWith("https://login.microsoftonline.com/", StringComparison.Ordinal);
    }

    internal static bool IsIdentityServerIssuer(string issuer)
    {
#if DEBUG
        if (issuer.StartsWith("https://localhost", StringComparison.Ordinal))
        {
            return true; // Allow localhost issuer in debug mode
        }
#endif
        return issuer.StartsWith("https://identityserver", StringComparison.Ordinal);
    }

    internal string ExtractUserObjectIds(TokenValidationResult validationResult, ExtensionGrantValidationContext context)
    {
        _logger.LogDebug("ExtractUserObjectIds called");
        var userObjectId = validationResult?.Claims?.FirstOrDefault(c => c.Type == Abstraction.Constants.ClaimNames.UserObjectId ||
                                                                         c.Type == Abstraction.Constants.ClaimNames.UserSubjectId)?.Value ?? string.Empty;
        _logger.LogDebug("Extracted userObjectId: {UserObjectId}", userObjectId);

        if (string.IsNullOrEmpty(userObjectId))
        {
            _logger.LogWarning("subject_token is missing '{UserObjectIdClaim}' claim", Abstraction.Constants.ClaimNames.UserObjectId);
            context.Result = new GrantValidationResult(TokenRequestErrors.InvalidRequest, $"subject_token is missing '{Abstraction.Constants.ClaimNames.UserObjectId}' claim");
            return string.Empty;
        }
        return userObjectId;
    }

    internal string ExtractClientIds(TokenValidationResult validationResult, ExtensionGrantValidationContext context)
    {
        _logger.LogDebug("ExtractClientIds called");
        var clientId = validationResult?.Claims?.FirstOrDefault(c => c.Type == JwtClaimTypes.ClientId ||
                                                                     c.Type == Abstraction.Constants.ClaimNamesEntra.ClientId)?.Value ?? string.Empty;
        _logger.LogDebug("Extracted clientId: {ClientId}", clientId);

        if (string.IsNullOrEmpty(clientId))
        {
            _logger.LogWarning("subject_token is missing {ClientIdClaim} claim", JwtClaimTypes.ClientId);
            context.Result = new GrantValidationResult(TokenRequestErrors.InvalidRequest, $"subject_token is missing {JwtClaimTypes.ClientId} claim");
            return string.Empty;
        }
        return clientId;
    }

    internal List<Claim> BuildClaims(TokenValidationResult validationResult, Claim? actorClaim = null)
    {
        _logger.LogDebug("BuildClaims called");

        var claims = new List<Claim>(validationResult?.Claims?.Where(c => _meaningfulClaimsInSubjectToken.Contains(c.Type)) ?? Array.Empty<Claim>());
        if (actorClaim != null)
        {
            claims.Add(actorClaim);
        }
        _logger.LogDebug("BuildClaims produced {ClaimsCount} claims", claims.Count);
        return claims;
    }

    internal Claim BuildActorClaim(TokenValidationResult validationResult, ExtensionGrantValidationContext context)
    {
        _logger.LogDebug("BuildActorClaim called");
        var actor = new Actor
        {
            ClientId = context.Request.Client.ClientId
        };

        // preserve the previous actor claim if exists
        var prevActor = validationResult?.Claims?.FirstOrDefault(c => c.Type == JwtClaimTypes.Actor)?.Value ?? string.Empty;
        if (!string.IsNullOrEmpty(prevActor))
        {
            try
            {
                var prevActorObj = JsonSerializer.Deserialize<Dictionary<string, object>>(prevActor);
                if (prevActorObj != null)
                {
                    _logger.LogDebug("Found previous actor claim {PrevActor}", prevActorObj);
                    actor = new Actor
                    {
                        ClientId = context.Request.Client.ClientId,
                        Act = prevActorObj,
                    };
                }
            }
            catch (JsonException ex)
            {
                _logger.LogWarning(ex, "Failed to deserialize previous actor claims");
            }
        }

        _logger.LogDebug("BuildActorClaim returning claim for clientId: {ClientId}", actor.ClientId);

        return new(JwtClaimTypes.Actor, JsonSerializer.Serialize(actor), IdentityServerConstants.ClaimValueTypes.Json);
    }

    private static readonly HashSet<string> _meaningfulClaimsInSubjectToken = new(StringComparer.OrdinalIgnoreCase)
    {
        JwtClaimTypes.Email,
        JwtClaimTypes.Name,
        JwtClaimTypes.SessionId,
        Abstraction.Constants.ClaimNames.UserObjectId,
        Abstraction.Constants.ClaimNames.UserPrincipalName,
        Abstraction.Constants.ClaimNames.UserOnPremisesSamAccountName,
    };

    private sealed class Actor
    {
        [JsonPropertyName(JwtClaimTypes.ClientId)]
        public string ClientId { get; set; } = string.Empty;

        [JsonPropertyName(JwtClaimTypes.Actor)]
        [JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)]
        public Dictionary<string, object>? Act { get; set; }
    }
}

