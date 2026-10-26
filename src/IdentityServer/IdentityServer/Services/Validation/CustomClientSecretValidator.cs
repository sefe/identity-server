// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

using Duende.IdentityModel;
using Duende.IdentityServer;
using Duende.IdentityServer.Events;
using Duende.IdentityServer.Models;
using Duende.IdentityServer.Services;
using Duende.IdentityServer.Stores;
using Duende.IdentityServer.Validation;

namespace IdentityServer.Services.Validation;

/// <summary>
/// Validates a client secret using the registered secret validators and parsers driven by the client configuration and auth flow.
/// </summary>
public class CustomClientSecretValidator : IClientSecretValidator
{
    private readonly ILogger _logger;
    private readonly IClientStore _clients;
    private readonly IEventService _events;
    private readonly ISecretsListValidator _validator;
    private readonly ISecretsListParser _parser;

    /// <summary>
    /// Initializes a new instance of the <see cref="CustomClientSecretValidator"/> class.
    /// </summary>
    /// <param name="clients">The clients.</param>
    /// <param name="parser">The parser.</param>
    /// <param name="validator">The validator.</param>
    /// <param name="events">The events.</param>
    /// <param name="logger">The logger.</param>
    public CustomClientSecretValidator(IClientStore clients, ISecretsListParser parser, ISecretsListValidator validator, IEventService events, ILogger<CustomClientSecretValidator> logger)
    {
        _clients = clients;
        _parser = parser;
        _validator = validator;
        _events = events;
        _logger = logger;
    }

    /// <summary>
    /// Validates secret of the current request.
    /// Note that ErrorDescription, if present, is not returned to the end user by design, for security reasons:
    ///     leaking details about client authentication failures (e.g., invalid secret, unknown client) could be exploited in brute-force or probing attacks.
    /// Implementation mimics the origianl <see cref="ClientSecretValidator"/> but follows stricter rules for client credentials flow - client secret must always be provided for the flow. 
    /// </summary>
    /// <param name="context">The context.</param>
    /// <returns></returns>
    public async Task<ClientSecretValidationResult> ValidateAsync(HttpContext context, CancellationToken cancellationToken)
    {
        _logger.LogDebug("Start client validation");

        var fail = new ClientSecretValidationResult
        {
            IsError = true,
            Error = OidcConstants.TokenErrors.InvalidClient
        };

        var parsedSecret = await _parser.ParseAsync(context, cancellationToken);
        if (parsedSecret == null)
        {
            await RaiseFailureEventAsync("unknown", "No client id found", cancellationToken);
            _logger.LogError("No client identifier found");

            fail.Error = OidcConstants.TokenErrors.InvalidRequest;
            fail.ErrorDescription = "No client identifier found in the request.";
            return fail;
        }

        // load client
        var client = await _clients.FindEnabledClientByIdAsync(parsedSecret.Id, cancellationToken);
        if (client == null)
        {
            await RaiseFailureEventAsync(parsedSecret.Id, "Unknown client", cancellationToken);
            _logger.LogError("No client with id '{ClientId}' found", parsedSecret.Id);
            fail.ErrorDescription = $"Client not found or not enabled.";
            return fail;
        }

        var grantType = await GetGrantTypeAsync(context, cancellationToken);

        SecretValidationResult? secretValidationResult = null;
        if (grantType != GrantType.ClientCredentials && (!client.RequireClientSecret || client.IsImplicitOnly()))
        {
            _logger.LogDebug("Public Client - skipping secret validation success");
        }
        else
        {
            secretValidationResult = await _validator.ValidateAsync(client.ClientSecrets, parsedSecret, cancellationToken);
            if (!secretValidationResult.Success)
            {
                await RaiseFailureEventAsync(client.ClientId, secretValidationResult.Error ?? "Invalid client secret", cancellationToken);
                _logger.LogError("Client secret validation failed for client {ClientId}: {Error}: {ErrorDescription}", client.ClientId, secretValidationResult.Error, secretValidationResult.ErrorDescription);
                fail.ErrorDescription = "Invalid client secret.";
                return fail;
            }
        }

        _logger.LogDebug("Client validation success");

        var success = new ClientSecretValidationResult
        {
            IsError = false,
            Client = client,
            Secret = parsedSecret,
            Confirmation = secretValidationResult?.Confirmation
        };

        await RaiseSuccessEventAsync(client.ClientId, parsedSecret.Type, cancellationToken);
        return success;
    }

    private static async Task<string?> GetGrantTypeAsync(HttpContext context, CancellationToken cancellationToken)
    {
        await context.Request.ReadFormAsync(cancellationToken);
        string? grantType = context.Request.Form[OidcConstants.TokenRequest.GrantType];
        return grantType ?? context.Request.Query[OidcConstants.TokenRequest.GrantType].FirstOrDefault();
    }

    private Task RaiseSuccessEventAsync(string clientId, string authMethod, CancellationToken cancellationToken)
    {
        Telemetry.Metrics.ClientSecretValidation(clientId, authMethod);
        return _events.RaiseAsync(new ClientAuthenticationSuccessEvent(clientId, authMethod), cancellationToken);
    }

    private Task RaiseFailureEventAsync(string clientId, string message, CancellationToken cancellationToken)
    {
        Telemetry.Metrics.ClientSecretValidationFailure(clientId, message);
        return _events.RaiseAsync(new ClientAuthenticationFailureEvent(clientId, message), cancellationToken);
    }
}
