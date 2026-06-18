using System.ComponentModel.DataAnnotations;
using IdentityServer.Abstraction.Entities.IdentityServerConfig;

namespace IdentityServer.Abstraction.Entities.Validation;

[AttributeUsage(AttributeTargets.Property, AllowMultiple = false)]
public class ClientGrantTypeValidationAttribute : ValidationAttribute
{
    protected override ValidationResult? IsValid(object? value, ValidationContext validationContext)
    {
        if (value == null)
        {
            return ValidationResult.Success;
        }

        if (value is string grantType)
        {
            return ValidateSingleGrantType(grantType, validationContext);
        }

        if (value is IEnumerable<string> grantTypes)
        {
            return ValidateGrantTypeCollection(grantTypes, validationContext);
        }

        return new ValidationResult($"Value is not of the expected type (string or IEnumerable<string>).",
            validationContext.GetMemberNames());
    }

    private static ValidationResult? ValidateSingleGrantType(string grantType, ValidationContext validationContext)
    {
        if (ClientGrantTypeNames.AllowedGrantsIds.Contains(grantType))
        {
            return ValidationResult.Success;
        }

        return CreateErrorResult(validationContext, grantType);
    }

    private static ValidationResult? ValidateGrantTypeCollection(IEnumerable<string> grantTypes, ValidationContext validationContext)
    {
        var invalidGrantTypes = grantTypes
            .Where(gt => !ClientGrantTypeNames.AllowedGrantsIds.Contains(gt))
            .ToArray();

        return invalidGrantTypes.Length == 0
           ? ValidationResult.Success
           : CreateErrorResult(validationContext, invalidGrantTypes);
    }

    private static ValidationResult CreateErrorResult(ValidationContext validationContext, params string[] grants)
    {
        var errorText = $"Invalid grant type(s): {string.Join(", ", grants)}. Allowed values are: {string.Join(", ", ClientGrantTypeNames.AllowedGrantsIds)}.";
        return new ValidationResult(errorText, validationContext.GetMemberNames());
    }
}
