// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

using IdentityServer.Abstraction.DTO.Export;

namespace IdentityServer.Abstraction.DTO.Import;

/// <summary>
/// Checks for inconsistencies in the import data.
/// </summary>
public static class RoleImportDtoValidationService<TRoleMapping> where TRoleMapping : RoleMappingValueObject
{
    public static bool IsValid(IDtoRoleImport<TRoleMapping> importDto, OperationStatus status)
    {
        if (!BasicValidation(importDto, status.Errors))
        {
            return false;
        }

        foreach (var role in importDto.Roles)
        {
            ValidateRole(role, status.Errors);
        }

        return !status.HasErrors;
    }

    private static bool BasicValidation(IDtoRoleImport<TRoleMapping> importDto, List<string> errors)
    {
        if (importDto == null)
        {
            errors.Add("Import object cannot be null.");
            return false;
        }

        if (importDto.Roles == null || importDto.Roles.Count == 0)
        {
            errors.Add("Import data contains no roles.");
            return false;
        }

        if (importDto.Roles.Any(role => role == null || string.IsNullOrEmpty(role.RoleName)))
        {
            errors.Add("At least one role is invalid and/or lacks a valid role name.");
            return false;
        }

        // find duplicated role names
        var roleNames = importDto.Roles.Select(r => r.RoleName).ToList();
        var duplicateRoleNames = roleNames.GroupBy(x => x, StringComparer.OrdinalIgnoreCase).Where(g => g.Count() > 1).Select(g => g.Key).ToList();
        if (duplicateRoleNames.Count != 0)
        {
            errors.Add($"Duplicate role names found: {string.Join(", ", duplicateRoleNames)}.");
            return false;
        }

        return true;
    }

    private static void ValidateRole(RoleValueObject<TRoleMapping> role, List<string> errors)
    {
        foreach (var mapping in role.Mappings.Where(m => string.IsNullOrWhiteSpace(m.MappingType) || string.IsNullOrWhiteSpace(m.Value)))
        {
            errors.Add($"Mapping type and value are required for each mapping in role '{role.RoleName}'.");
        }

        // Validate that all mappings have unique type, value, and description within the same role
        var mappingTypes = role.Mappings.GroupBy(m => m.MappingType).ToList();
        foreach (var mappingGroup in mappingTypes)
        {
            var mappingValues = mappingGroup.GroupBy(m => m.Value, StringComparer.OrdinalIgnoreCase).ToList();
            if (mappingValues.Any(g => g.Count() > 1))
            {
                errors.Add($"Duplicate mapping values found for type '{mappingGroup.Key}' in role '{role.RoleName}': {string.Join(", ", mappingValues.Select(g => g.Key))}");
            }
        }
    }
}
