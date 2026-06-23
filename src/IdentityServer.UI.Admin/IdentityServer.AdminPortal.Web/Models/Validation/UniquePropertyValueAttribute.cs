// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

using System.ComponentModel.DataAnnotations;

namespace IdentityServer.AdminPortal.Web.Models.Validation;

[AttributeUsage(AttributeTargets.Class, AllowMultiple = false, Inherited = true)]
public class UniquePropertyValueAttribute : ValidationAttribute
{
    private readonly IEnumerable<string> _memberNames;
    private readonly string _propertyDisplayName;

    public UniquePropertyValueAttribute(string propertyName, string propertyDisplayName)
    {
        _memberNames = new[] { propertyName };
        _propertyDisplayName = propertyDisplayName;
    }

    protected override ValidationResult? IsValid(object? value, ValidationContext validationContext)
    {
        var instance = validationContext.ObjectInstance;
        if (instance is not IHasUniquePropertyValue dto)
        {
            return new ValidationResult(
                $"{nameof(UniquePropertyValueAttribute)} can only be applied to object implementing interface {typeof(IHasUniquePropertyValue).Name}.",
                _memberNames);
        }

        if (!string.IsNullOrEmpty(dto.UniqueProperty))
        {
            var trimmedPropertyValue = dto.UniqueProperty.Trim();
            if (dto.AlreadyExistingUniquePropertyValues.Contains(trimmedPropertyValue))
            {
                return new ValidationResult($"{_propertyDisplayName} '{trimmedPropertyValue}' already exists.", _memberNames);
            }
        }

        return ValidationResult.Success;
    }
}
