using System.ComponentModel.DataAnnotations;

namespace IdentityServer.Abstraction.Entities.Validation;

/// <summary>
/// Validates that a string is a valid redirect (reply) URI format.
/// Valid format is an absolute URI without wildcards.
/// There are some exceptions for loopback addresses.
/// </summary>
[AttributeUsage(AttributeTargets.Property, AllowMultiple = false)]
public class ClientRedirectUriValidationAttribute : ValidationAttribute
{
    private readonly string _parameterName;

    public ClientRedirectUriValidationAttribute(string parameterName = "Redirect URI")
    {
        _parameterName = parameterName;
    }

    protected override ValidationResult? IsValid(object? value, ValidationContext validationContext)
    {
        var redirectUri = value?.ToString();
        var memberNames = validationContext.GetMemberNames();

        if (string.IsNullOrWhiteSpace(redirectUri))
        {
            return new ValidationResult($"{_parameterName} cannot be null or empty.", memberNames);
        }

        if (redirectUri.Contains('*'))
        {
            return new ValidationResult($"{_parameterName} cannot contain wildcards.", memberNames);
        }

        // On the client side, If redirectUri equals "/", it creates the "file:///" uri
        if (!Uri.TryCreate(redirectUri, UriKind.Absolute, out _) || redirectUri == "/")
        {
            return new ValidationResult($"{_parameterName} must be an absolute URI.", memberNames);
        }

        return ValidationResult.Success;
    }
}
