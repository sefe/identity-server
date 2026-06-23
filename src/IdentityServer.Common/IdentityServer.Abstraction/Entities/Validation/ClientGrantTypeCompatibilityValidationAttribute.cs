// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

using System.ComponentModel.DataAnnotations;
using IdentityServer.Abstraction.Entities.IdentityServerConfig;

namespace IdentityServer.Abstraction.Entities.Validation;

/// <summary>
/// Validates that no incompatible grant type pairs are present in the collection.
/// </summary>
[AttributeUsage(AttributeTargets.Property, AllowMultiple = false)]
public class ClientGrantTypeCompatibilityValidationAttribute : ValidationAttribute
{
    protected override ValidationResult? IsValid(object? value, ValidationContext validationContext)
    {
        if (value == null)
        {
            return ValidationResult.Success;
        }

        if (value is not IEnumerable<string> grantTypes)
        {
            return new ValidationResult("Value is not of the expected type (IEnumerable<string>).", validationContext.GetMemberNames());
        }

        var grantTypeList = grantTypes as ICollection<string> ?? grantTypes.ToList();
        if (grantTypeList.Count < 2)
        {
            return ValidationResult.Success;
        }

        var incompatiblePairs = ClientGrantTypeNames.IncompatibleGrantPairs
            .Where(pair => grantTypeList.Contains(pair.Key) && grantTypeList.Contains(pair.Value))
            .ToList();

        if (incompatiblePairs.Count != 0)
        {
            var incompatibleDescriptions = incompatiblePairs
                       .Select(pair =>
                           $"'{ClientGrantTypeNames.AllGrantTypes[pair.Key]}' and '{ClientGrantTypeNames.AllGrantTypes[pair.Value]}'")
                       .ToList();
            var errorText = $"Incompatible grant types: {string.Join("; ", incompatibleDescriptions)}.";

            return new ValidationResult(errorText, validationContext.GetMemberNames());
        }

        return ValidationResult.Success;
    }
}
