using System.ComponentModel.DataAnnotations;

namespace IdentityServer.Abstraction.Entities.Validation;

/// <summary>
/// Attribute to validate that the supplied string value is a valid GUID in format 'D' (with hyphens).
/// </summary>
[AttributeUsage(AttributeTargets.Property | AttributeTargets.Field | AttributeTargets.Parameter, AllowMultiple = false)]
public class ValidGuidAttribute : ValidationAttribute
{
    private const string _defaultErrorMessage = "Value must be a valid non-empty GUID 'xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx'.";
    private const string _typeMismatchErrorMessage = "Value is not of the expected type (string).";

    protected override ValidationResult? IsValid(object? value, ValidationContext validationContext)
    {
        if (value is string stringValue)
        {
            if (Guid.TryParseExact(stringValue, "D", out var result) && result != Guid.Empty)
            {
                return ValidationResult.Success;
            }
            return new ValidationResult(ErrorMessage ?? _defaultErrorMessage, validationContext.GetMemberNames());
        }
        return new ValidationResult(_typeMismatchErrorMessage, validationContext.GetMemberNames());
    }
}
