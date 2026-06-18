using IdentityServer.Abstraction.DTO;
using IdentityServer.Abstraction.DTO.ApiResources;
using IdentityServer.Abstraction.DTO.Clients;
using IdentityServer.Abstraction.DTO.Export;
using IdentityServer.Abstraction.DTO.Import;
using IdentityServer.Abstraction.Extensions;
using IdentityServer.AdminPortal.Web.Models.RoleImport;

namespace IdentityServer.AdminPortal.Web.Services.RoleImport;

public interface IRoleImportComparer<TRoleMapping> where TRoleMapping : RoleMappingValueObject
{
    Task<List<RoleComparisonModel>> CompareWithAsync(IDtoRoleImport<TRoleMapping> importDto, ImportStrategy importStrategy);
}

public class RoleImportComparer<TRoleMapping> : IRoleImportComparer<TRoleMapping> where TRoleMapping : RoleMappingValueObject
{
    private readonly List<RoleValueObject<TRoleMapping>> _existingRoles;

    public RoleImportComparer(List<ApiResourcePropertyRoleDtoRead> existingRoles, Func<ApiResourcePropertyRoleMappingDtoRead, TRoleMapping> converter)
    {
        _existingRoles = existingRoles.Select(
            r => new RoleValueObject<TRoleMapping>
            {
                RoleName = r.RoleName,
                Mappings = r.Mappings.Select(rm => converter(rm)).ToList()
            }).ToList();
    }

    public RoleImportComparer(List<ClientPropertyRoleDtoRead> existingRoles, Func<ClientPropertyRoleMappingDtoRead, TRoleMapping> converter)
    {
        _existingRoles = existingRoles.Select(
            r => new RoleValueObject<TRoleMapping>
            {
                RoleName = r.RoleName,
                Mappings = r.Mappings.Select(rm => converter(rm)).ToList()
            }).ToList();
    }

    public Task<List<RoleComparisonModel>> CompareWithAsync(IDtoRoleImport<TRoleMapping> importDto, ImportStrategy importStrategy)
    {
        return importStrategy switch
        {
            ImportStrategy.Replace => RoleReplaceComparer.CompareRolesAsync(_existingRoles, importDto.Roles),
            ImportStrategy.Add => RoleAddComparer.CompareRolesAsync(_existingRoles, importDto.Roles),
            _ => throw new InvalidOperationException($"Import strategy '{importStrategy}' is not supported")
        };
    }
}

public static class RoleReplaceComparer
{
    public static Task<List<RoleComparisonModel>> CompareRolesAsync<TRoleMapping>(
        List<RoleValueObject<TRoleMapping>> existingRoles,
        List<RoleValueObject<TRoleMapping>> importedRoles) where TRoleMapping : RoleMappingValueObject
    {
        var result = new List<RoleComparisonModel>();
        var existingRoleNames = existingRoles.Select(r => r.RoleName).ToHashSet(StringComparer.OrdinalIgnoreCase);
        var importedRoleNames = importedRoles.Select(r => r.RoleName).ToHashSet(StringComparer.OrdinalIgnoreCase);
        // Roles only in existing resource
        foreach (var role in existingRoles.Where(r => !importedRoleNames.Contains(r.RoleName)))
        {
            var comparedRole = new RoleComparisonModel
            {
                RoleName = role.RoleName,
                RoleState = ComparisonState.Removed,
            };
            comparedRole.Mappings = role.Mappings?.Select(m => new RoleMappingComparisonModel
            {
                Existing = m,
                Imported = EmptyRoleMappingValueObject.Instance,
                State = ComparisonState.Removed,
                Parent = comparedRole
            }).ToList() ?? new List<RoleMappingComparisonModel>();

            result.Add(comparedRole);
        }
        // Roles only in import file
        foreach (var role in importedRoles.Where(r => !existingRoleNames.Contains(r.RoleName)))
        {
            var comparedRole = new RoleComparisonModel
            {
                RoleName = role.RoleName,
                RoleState = ComparisonState.Added,
            };
            comparedRole.Mappings = role.Mappings?.Select(m => new RoleMappingComparisonModel
            {
                Imported = m,
                Existing = EmptyRoleMappingValueObject.Instance,
                State = ComparisonState.Added,
                Parent = comparedRole
            }).ToList() ?? new List<RoleMappingComparisonModel>();
            result.Add(comparedRole);
        }
        // Roles in both (with mapping differences)
        foreach (var role in importedRoles.Where(r => existingRoleNames.Contains(r.RoleName)))
        {
            var existingRole = existingRoles.First(r => string.Equals(r.RoleName, role.RoleName, StringComparison.OrdinalIgnoreCase));

            var comparisonModel = new RoleComparisonModel { RoleName = role.RoleName };

            comparisonModel.Mappings = CompareRoleMappings(
                existingRole.Mappings ?? new List<TRoleMapping>(),
                role.Mappings ?? new List<TRoleMapping>(), comparisonModel);

            result.Add(comparisonModel);
        }

        return Task.FromResult(result);
    }

    private static List<RoleMappingComparisonModel> CompareRoleMappings<TRoleMapping>(
        List<TRoleMapping> existingMappings,
        List<TRoleMapping> importedMappings, RoleComparisonModel parent) where TRoleMapping : RoleMappingValueObject
    {
        var comparisonModels = new List<RoleMappingComparisonModel>();
        // Mappings only in existing resource
        foreach (var mapping in existingMappings.Where(m => !importedMappings.Any(im => im.MappingType.IsSameLax(m.MappingType) && im.Value.IsSameLax(m.Value))))
        {
            comparisonModels.Add(new RoleMappingComparisonModel
            {
                Existing = mapping,
                Imported = EmptyRoleMappingValueObject.Instance,
                State = ComparisonState.Removed,
                Parent = parent
            });
        }
        // Mappings only in import file
        foreach (var mapping in importedMappings.Where(m => !existingMappings.Any(em => em.MappingType.IsSameLax(m.MappingType) && em.Value.IsSameLax(m.Value))))
        {
            comparisonModels.Add(new RoleMappingComparisonModel
            {
                Imported = mapping,
                Existing = EmptyRoleMappingValueObject.Instance,
                State = ComparisonState.Added,
                Parent = parent
            });
        }
        // Mappings in both (with differences)
        foreach (var mapping in importedMappings.Where(m => existingMappings.Any(em => em.MappingType.IsSameLax(m.MappingType) && em.Value.IsSameLax(m.Value))))
        {
            var existingMapping = existingMappings.First(em => em.MappingType.IsSameLax(mapping.MappingType) && em.Value.IsSameLax(mapping.Value));
            comparisonModels.Add(new RoleMappingComparisonModel
            {
                Imported = mapping,
                Existing = existingMapping,
                State = string.Equals(existingMapping.Description, mapping.Description, StringComparison.OrdinalIgnoreCase) ? ComparisonState.Unchanged : ComparisonState.Changed,
                Parent = parent
            });
        }

        return comparisonModels;
    }
}

public static class RoleAddComparer
{
    public static Task<List<RoleComparisonModel>> CompareRolesAsync<TRoleMapping>(
        List<RoleValueObject<TRoleMapping>> existingRoles,
        List<RoleValueObject<TRoleMapping>> importedRoles) where TRoleMapping : RoleMappingValueObject
    {
        var result = new List<RoleComparisonModel>();
        var existingRoleNames = existingRoles.Select(r => r.RoleName).ToHashSet(StringComparer.OrdinalIgnoreCase);
        var importedRoleNames = importedRoles.Select(r => r.RoleName).ToHashSet(StringComparer.OrdinalIgnoreCase);

        // Roles only in import file
        foreach (var role in importedRoles.Where(r => !existingRoleNames.Contains(r.RoleName)))
        {
            var comparedRole = new RoleComparisonModel
            {
                RoleName = role.RoleName,
                RoleState = ComparisonState.Added,
            };

            comparedRole.Mappings = role.Mappings?.Select(m => new RoleMappingComparisonModel
            {
                Imported = m,
                Existing = EmptyRoleMappingValueObject.Instance,
                State = ComparisonState.Added,
                Parent = comparedRole
            }).ToList() ?? new List<RoleMappingComparisonModel>();

            result.Add(comparedRole);
        }

        // Roles in both (with mapping differences)
        foreach (var role in importedRoles.Where(r => existingRoleNames.Contains(r.RoleName)))
        {
            var existingRole = existingRoles.First(r => r.RoleName.IsSameLax(role.RoleName));

            var comparisonModel = new RoleComparisonModel { RoleName = role.RoleName };

            comparisonModel.Mappings = CompareRoleMappings(
                existingRole.Mappings ?? new List<TRoleMapping>(),
                role.Mappings ?? new List<TRoleMapping>(), comparisonModel);

            result.Add(comparisonModel);
        }

        // Roles only in existing resource without modified mappings
        foreach (var role in existingRoles.Where(r => !importedRoleNames.Contains(r.RoleName)))
        {
            var comparedRole = new RoleComparisonModel
            {
                RoleName = role.RoleName,
                RoleState = ComparisonState.Unchanged,
            };

            comparedRole.Mappings = role.Mappings?.Select(m => new RoleMappingComparisonModel
            {
                Existing = m,
                Imported = EmptyRoleMappingValueObject.Instance,
                State = ComparisonState.Unchanged,
                Parent = comparedRole
            }).ToList() ?? new List<RoleMappingComparisonModel>();

            result.Add(comparedRole);
        }

        return Task.FromResult(result);
    }

    private static List<RoleMappingComparisonModel> CompareRoleMappings<TRoleMapping>(
        List<TRoleMapping> existingMappings,
        List<TRoleMapping> importedMappings, RoleComparisonModel parent) where TRoleMapping : RoleMappingValueObject
    {
        var comparisonModels = new List<RoleMappingComparisonModel>();
        // Mappings only in existing resource
        foreach (var mapping in existingMappings.Where(m => !importedMappings.Any(im => im.MappingType.IsSameLax(m.MappingType) && im.Value.IsSameLax(m.Value))))
        {
            comparisonModels.Add(new RoleMappingComparisonModel
            {
                Existing = mapping,
                Imported = EmptyRoleMappingValueObject.Instance,
                State = ComparisonState.Unchanged,
                Parent = parent
            });
        }
        // Mappings only in import file
        foreach (var mapping in importedMappings.Where(m => !existingMappings.Any(em => em.MappingType.IsSameLax(m.MappingType) && em.Value.IsSameLax(m.Value))))
        {
            comparisonModels.Add(new RoleMappingComparisonModel
            {
                Imported = mapping,
                Existing = EmptyRoleMappingValueObject.Instance,
                State = ComparisonState.Added,
                Parent = parent
            });
        }
        // Mappings in both (with differences)
        foreach (var mapping in importedMappings.Where(m => existingMappings.Any(em => em.MappingType.IsSameLax(m.MappingType) && em.Value.IsSameLax(m.Value))))
        {
            var existingMapping = existingMappings.First(em => em.MappingType.IsSameLax(mapping.MappingType) && em.Value.IsSameLax(mapping.Value));
            comparisonModels.Add(new RoleMappingComparisonModel
            {
                Imported = mapping,
                Existing = existingMapping,
                State = string.Equals(existingMapping.Description, mapping.Description, StringComparison.OrdinalIgnoreCase) ? ComparisonState.Unchanged : ComparisonState.Conflict,
                Parent = parent
            });
        }

        return comparisonModels;
    }
}
