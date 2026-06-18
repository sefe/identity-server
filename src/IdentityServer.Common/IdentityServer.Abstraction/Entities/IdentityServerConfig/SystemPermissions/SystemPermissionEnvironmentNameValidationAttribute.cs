using System.ComponentModel.DataAnnotations;

namespace IdentityServer.Abstraction.Entities.IdentityServerConfig.SystemPermissions;

[AttributeUsage(AttributeTargets.Property)]
public class SystemPermissionEnvironmentNameValidationAttribute : ValidationAttribute
{
    protected override ValidationResult? IsValid(object? value, ValidationContext validationContext)
    {
        if (value == null)
        {
            return new ValidationResult("Environment cannot be null.");
        }
        var valueString = value.ToString();
        if (string.IsNullOrEmpty(valueString))
        {
            return new ValidationResult("Environment cannot be null.");
        }

        if (!SystemPermissionEnvironmentNames.EnvironmentNames.Contains(valueString))
        {
            return new ValidationResult($"The environment '{valueString}' is not valid.");
        }

        return ValidationResult.Success;
    }
}
