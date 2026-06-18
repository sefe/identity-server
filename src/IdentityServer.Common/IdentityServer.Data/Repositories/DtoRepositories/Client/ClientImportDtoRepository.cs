using System.Security.Claims;
using Microsoft.Extensions.Logging;
using IdentityServer.Abstraction.Contracts;
using IdentityServer.Abstraction.DTO.Export;
using IdentityServer.Abstraction.DTO.Import;
using IdentityServer.Abstraction.Entities.IdentityServerConfig;
using IdentityServer.Abstraction.Exceptions;
using IdentityServer.Data.DuendeEntityExtensions;
using IdentityServer.Data.Entities.Roles;
using IdentityServer.Data.Services;

namespace IdentityServer.Data.Repositories.DtoRepositories.Client;

/// <summary>
/// Responsible for bulk changes for <seealso cref="ClientExt"/> entities.
/// </summary>
internal class ClientImportDtoRepository :
    IDtoImportRepository<ClientRoleImportDto>
{
    private readonly IStorage<ClientExt> _clientStorage;
    private readonly IStorage<ClientRole> _roleStorage;
    private readonly IPermissionChecker _permissionChecker;
    private readonly ILogger<ClientImportDtoRepository> _logger;
    private readonly IRoleMappingValidationService _roleMappingValidationService;

    public ClientImportDtoRepository(
        IStorage<ClientExt> clientStorage,
        IStorage<ClientRole> roleStorage,
        IPermissionChecker permissionChecker,
        ILogger<ClientImportDtoRepository> logger,
        IRoleMappingValidationService roleMappingValidationService)
    {
        _clientStorage = clientStorage;
        _roleStorage = roleStorage;
        _permissionChecker = permissionChecker;
        _logger = logger;
        _roleMappingValidationService = roleMappingValidationService;
    }

    public async Task<OperationStatus> ImportAsync(ClaimsPrincipal user, int id, ClientRoleImportDto resource)
    {
        var currentClient = await _clientStorage.GetByIdAsync(id) ?? throw new EntityNotFoundException($"Client with Id {id} was not found.");
        _ = await _permissionChecker.GetAccessRoleOrThrowIfNoAccessToEnvAsync(user, currentClient.SystemPermissionEnvironmentId, EntityAccessType.Update, currentClient.ToString()!);

        var validationSummary = await ValidateImportImplAsync(id, resource);
        if (validationSummary.HasErrors)
        {
            throw new ImportValidationException("Role mappings are invalid.", validationSummary);
        }

        switch (resource.ImportStrategy)
        {
            case ImportStrategy.Replace:
                await ReplaceClientRoles(resource, currentClient);
                break;
            case ImportStrategy.Add:
                await MergeAddClientRoles(resource, currentClient);
                break;
            default:
                throw new ImportValidationException("Unknown import strategy for Client roles.", validationSummary);
        }

        validationSummary.IsCompleted = true;

        return validationSummary;
    }

    public async Task<OperationStatus> ValidateImportAsync(ClaimsPrincipal user, int id, ClientRoleImportDto resource)
    {
        var currentClient = await _clientStorage.GetByIdAsync(id) ?? throw new EntityNotFoundException($"Client with Id {id} was not found.");
        _ = await _permissionChecker.GetAccessRoleOrThrowIfNoAccessToEnvAsync(user, currentClient.SystemPermissionEnvironmentId, EntityAccessType.Read, currentClient.ToString()!);

        return await ValidateImportImplAsync(id, resource);
    }

    internal async Task<OperationStatus> ValidateImportImplAsync(int id, ClientRoleImportDto resource)
    {
        var validationSummary = new OperationStatus();

        // validate the logical structural integrity of the import
        RoleImportDtoValidationService<ClientRoleMappingValueObject>.IsValid(resource, validationSummary);

        // validate values and descriptions
        var allRoleMappings = resource.Roles.SelectMany(r => r.Mappings).Cast<RoleMappingValueObject>().ToList();
        await _roleMappingValidationService.ValidateImportRoleMappingsAsync(allRoleMappings, validationSummary);

        _logger.LogInformation("Validating import for Client {ClientId} with {NumberOfRoles} roles and {NumberOfRoleMappings} mappings. Validation summary: {ValidationSummary}",
            id, resource.Roles.Count, allRoleMappings.Count, validationSummary);

        return validationSummary;
    }

    /// <summary>
    /// COMPLETELY replacing the existing roles with the new ones.
    /// </summary>
    internal async Task ReplaceClientRoles(ClientRoleImportDto resource, ClientExt currentClient)
    {
        _logger.LogInformation("Replacing {NumberOfRoles} and {NumberOfRoleMappings} for Client {ClientName} (Id: {ClientId}) with imported {NumberOfImportedRoles} and {NumberOfImportedRoleMappings}.",
            currentClient.Roles.Count,
            currentClient.Roles.SelectMany(r => r.Mappings).Count(),
            currentClient.ClientName,
            currentClient.Id,
            resource.Roles.Count,
            resource.Roles.SelectMany(r => r.Mappings).Count()
        );

        await RemoveAllExistingRoles(currentClient);

        // roles are imported in a two-step process: first we need IDs of the roles, then we can add mappings.
        foreach (var roleToImport in resource.Roles)
        {
            currentClient.Roles.Add(new ClientRole
            {
                RoleName = roleToImport.RoleName
            });
        }

        // now we can add mappings
        foreach (var roleToImport in resource.Roles)
        {
            var roleToUpdate = currentClient.Roles.First(r => string.Equals(r.RoleName, roleToImport.RoleName, StringComparison.OrdinalIgnoreCase));

            roleToUpdate.Mappings.AddRange(roleToImport.Mappings.Select(mapping => new ClientRoleMapping
            {
                ClientRoleId = roleToUpdate.Id,
                Role = roleToUpdate,
                MappingType = Enum.Parse<ClientRoleMapType>(mapping.MappingType),
                Value = mapping.Value,
                Description = mapping.Description,
            }));
        }

        await _clientStorage.UpdateAsync(currentClient);
    }

    private async Task RemoveAllExistingRoles(ClientExt currentClient)
    {
        // Update audit timestamps on the role and all its mappings before deletion
        var updatedTime = DateTime.UtcNow;

        foreach (var role in currentClient.Roles)
        {
            role.Updated = updatedTime;
            if (role.Mappings != null)
            {
                foreach (var mapping in role.Mappings)
                {
                    mapping.Updated = updatedTime;
                }
            }
            await _roleStorage.UpdateAsync(role);
        }

        currentClient.Roles.Clear();
    }

    /// <summary>
    /// Merges imported roles and mappings into the existing API resource.
    /// Adds new roles, updates mappings for existing roles, and leaves untouched roles as-is.
    /// Does not remove any existing roles or mappings.
    /// </summary>
    internal async Task MergeAddClientRoles(ClientRoleImportDto resource, ClientExt currentClient)
    {
        _logger.LogInformation(
            "Merging (add) {NumberOfImportedRoles} roles and {NumberOfImportedRoleMappings} mappings into Client {ClientName} (Id: {ClientId}). Existing roles: {NumberOfRoles}, mappings: {NumberOfRoleMappings}.",
            resource.Roles.Count,
            resource.Roles.SelectMany(r => r.Mappings).Count(),
            currentClient.ClientName,
            currentClient.Id,
            currentClient.Roles.Count,
            currentClient.Roles.SelectMany(r => r.Mappings).Count()
        );

        // Add or update roles
        foreach (var roleNameToImport in resource.Roles.Select(roleToImport => roleToImport.RoleName))
        {
            var existingRole = currentClient.Roles.FirstOrDefault(r => string.Equals(r.RoleName, roleNameToImport, StringComparison.OrdinalIgnoreCase));

            if (existingRole == null)
            {
                // Add new role
                var newRole = new Entities.Roles.ClientRole
                {
                    RoleName = roleNameToImport
                };
                currentClient.Roles.Add(newRole);
            }
        }

        // Add mappings to roles (only add new mappings, do not remove or update existing ones)
        foreach (var roleToImport in resource.Roles)
        {
            var roleToUpdate = currentClient.Roles.First(r => string.Equals(r.RoleName, roleToImport.RoleName, StringComparison.OrdinalIgnoreCase));

            foreach (var mapping in roleToImport.Mappings)
            {
                // Only add mapping if it does not already exist (by MappingType and Value)
                bool mappingExists = roleToUpdate.Mappings.Any(m =>
                    m.MappingType == Enum.Parse<ClientRoleMapType>(mapping.MappingType) &&
                    string.Equals(m.Value, mapping.Value, StringComparison.OrdinalIgnoreCase));

                if (!mappingExists)
                {
                    roleToUpdate.Mappings.Add(new Entities.Roles.ClientRoleMapping
                    {
                        ClientRoleId = roleToUpdate.Id,
                        Role = roleToUpdate,
                        MappingType = Enum.Parse<ClientRoleMapType>(mapping.MappingType),
                        Value = mapping.Value,
                        Description = mapping.Description,
                    });
                }
            }
        }

        await _clientStorage.UpdateAsync(currentClient);
    }
}
