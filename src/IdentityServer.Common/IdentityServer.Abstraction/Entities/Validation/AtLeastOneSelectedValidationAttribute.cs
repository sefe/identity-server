// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

using System.ComponentModel.DataAnnotations;

namespace IdentityServer.Abstraction.Entities.Validation;

/// <summary>
/// Validates that at least one Selectable in the IEnumerable is selected (IsSelected == true).
/// </summary>
[AttributeUsage(AttributeTargets.Property | AttributeTargets.Field, AllowMultiple = false)]
public class AtLeastOneSelectedValidationAttribute : ValidationAttribute
{
    private const string _defaultErrorMessage = "At least one item must be selected.";

    protected override ValidationResult? IsValid(object? value, ValidationContext validationContext)
    {
        if (value is IEnumerable<Selectable> enumerable)
        {
            if (enumerable.Any(_ => _.IsSelected))
            {
                return ValidationResult.Success;
            }

            // None selected
            return new ValidationResult(ErrorMessage ?? _defaultErrorMessage, validationContext.GetMemberNames());
        }
        // Not an IEnumerable or null
        return ValidationResult.Success;
    }
}
