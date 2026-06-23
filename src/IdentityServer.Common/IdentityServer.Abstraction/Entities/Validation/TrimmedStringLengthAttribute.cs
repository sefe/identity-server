// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

using System.ComponentModel.DataAnnotations;

namespace IdentityServer.Abstraction.Entities.Validation;

[AttributeUsage(AttributeTargets.Property | AttributeTargets.Field, AllowMultiple = false)]
public class TrimmedStringLengthAttribute : ValidationAttribute
{
    /// <summary>
    ///     Gets or sets the minimum acceptable length of the trimmed string
    /// </summary>
    public int MinimumLength { get; set; } = 0;

    /// <summary>
    ///     Gets or sets the maximum acceptable length of the trimmed string
    /// </summary>
    public int MaximumLength { get; set; } = int.MaxValue;

    protected override ValidationResult? IsValid(object? value, ValidationContext validationContext)
    {
        if (value == null)
        {
            return ValidationResult.Success;
        }

        if (value is string strValue)
        {
            var length = strValue.Trim().Length;
            return length >= MinimumLength && length <= MaximumLength ?
                ValidationResult.Success :
                    new ValidationResult(ErrorMessage ?? $"The value must be between {MinimumLength} and {MaximumLength} characters long.", validationContext.GetMemberNames());
        }

        return new ValidationResult("Value is not a string.", validationContext.GetMemberNames());
    }
}
