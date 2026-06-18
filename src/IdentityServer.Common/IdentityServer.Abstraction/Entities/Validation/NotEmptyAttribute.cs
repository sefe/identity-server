using System.Collections;
using System.ComponentModel.DataAnnotations;

namespace IdentityServer.Abstraction.Entities.Validation;

/// <summary>
/// Attribute to validate that a collection is not empty.
/// Using this attribute on a non-enumerable type will always return false.
/// Null value resuls in false.
/// </summary>
[AttributeUsage(AttributeTargets.Property | AttributeTargets.Field | AttributeTargets.Parameter, AllowMultiple = false)]
public class NotEmptyAttribute : ValidationAttribute
{
    protected override ValidationResult? IsValid(object? value, ValidationContext validationContext)
    {
        if (value is IEnumerable collection)
        {
            var enumerator = collection.GetEnumerator();
            try
            {
                return enumerator.MoveNext() ?
                    ValidationResult.Success :
                    new ValidationResult(ErrorMessage ?? "At least one value is required.", validationContext.GetMemberNames());
            }
            catch
            {
                return new ValidationResult("Validation failed.", validationContext.GetMemberNames());
            }
            finally
            {
                (enumerator as IDisposable)?.Dispose();
            }
        }
        return new ValidationResult("Value is not of the expected type (IEnumerable<string>).", validationContext.GetMemberNames());
    }
}
