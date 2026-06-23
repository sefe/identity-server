// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

using System.ComponentModel.DataAnnotations;

namespace IdentityServer.Abstraction.Entities.Validation;

/// <summary>
/// Validates that a string is a valid CORS origin format.
/// Valid format is limited to URLs with scheme (http/https), host, and optional port
/// </summary>
[AttributeUsage(AttributeTargets.Property, AllowMultiple = false)]
public class ClientCorsOriginValidationAttribute : ValidationAttribute
{
    protected override ValidationResult? IsValid(object? value, ValidationContext validationContext)
    {
        var origin = value?.ToString();

        IEnumerable<string> memberNames = validationContext.GetMemberNames();

        if (string.IsNullOrEmpty(origin))
        {
            return new ValidationResult("CORS origin must not be empty.", memberNames);
        }

        if (origin == "*")
        {
            return new ValidationResult("Wildcard CORS origin is not allowed.", memberNames);
        }

        if (origin.EndsWith('/'))
        {
            return new ValidationResult("CORS origin must end with hostname or port number.", memberNames);
        }

        try
        {
            if (!origin.StartsWith("http://", StringComparison.OrdinalIgnoreCase) &&
                !origin.StartsWith("https://", StringComparison.OrdinalIgnoreCase))
            {
                return new ValidationResult("CORS origin must start with 'http://' or 'https://'.", memberNames);
            }

            var uri = new Uri(origin);

            if (!string.IsNullOrEmpty(uri.AbsolutePath) && uri.AbsolutePath != "/")
            {
                return new ValidationResult("CORS origins shouldn't have paths.", memberNames);
            }

            if (!string.IsNullOrEmpty(uri.Query))
            {
                return new ValidationResult("CORS origins shouldn't have query strings.", memberNames);
            }

            if (!string.IsNullOrEmpty(uri.Fragment))
            {
                return new ValidationResult("CORS origins shouldn't have fragments.", memberNames);
            }

            return ValidationResult.Success;
        }
        catch
        {
            return new ValidationResult("Failed to validate CORS origin.", memberNames);
        }
    }
}
