// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

using Duende.IdentityServer.Validation;
using Microsoft.Extensions.Options;
using IdentityServer.Abstraction.Configs;

namespace IdentityServer.Services.Validation;

/// <summary>
/// Custom introspection request validator that decorates default behavior with custom logging based on the application settings.
/// Introspection endpoint is meant to work with reference tokens only
/// but no checks are built in to ensure that a particular request deals with a reference token.
/// </summary>
/// <seealso cref="IIntrospectionRequestValidator" />
internal class CustomIntrospectionRequestValidator : IIntrospectionRequestValidator
{
    private readonly IIntrospectionRequestValidator _defaultValidator;
    private readonly CustomTokenLoggingSettings _loggingSettings;
    private readonly ILogger<CustomIntrospectionRequestValidator> _logger;

    public CustomIntrospectionRequestValidator(IIntrospectionRequestValidator defaultValidator, IOptions<CustomTokenLoggingSettings> loggingSettings, ILogger<CustomIntrospectionRequestValidator> logger)
    {
        _defaultValidator = defaultValidator;
        _loggingSettings = loggingSettings.Value;
        _logger = logger;
    }

    public async Task<IntrospectionRequestValidationResult> ValidateAsync(IntrospectionRequestValidationContext context)
    {
        var tokenPreview = GetObfuscatedToken(context);
        _logger.LogInformation("Introspecting reference token for API '{ApiResourceId}' / Application '{ClientId}'. TokenPreview={TokenPreview}",
            context.Api?.Name ?? "", context.Client?.ClientId ?? "", tokenPreview ?? "");

        var result = await _defaultValidator.ValidateAsync(context);
        return result;
    }

    private string? GetObfuscatedToken(IntrospectionRequestValidationContext context)
    {
        var rawToken = context.Parameters["token"];
        if (string.IsNullOrEmpty(rawToken))
        {
            return null;
        }

        var visibleLength = _loggingSettings.ReferenceTokenDefaultVisibleLength;
        var partialTokenLength = rawToken!.Length > (visibleLength * 2) ? visibleLength : (rawToken.Length / 2);
        return string.Concat("***", rawToken.AsSpan(rawToken.Length - partialTokenLength));
    }
}
