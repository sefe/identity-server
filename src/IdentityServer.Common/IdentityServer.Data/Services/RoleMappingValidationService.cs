using IdentityServer.Abstraction.Contracts;
using IdentityServer.Abstraction.Contracts.MicrosoftGraph;
using IdentityServer.Abstraction.DTO.Export;
using IdentityServer.Abstraction.DTO.Import;
using IdentityServer.Abstraction.Entities.EntraEntities;
using IdentityServer.Abstraction.Entities.IdentityServerConfig;
using IdentityServer.Data.DuendeEntityExtensions;
using IdentityServer.Data.Entities.Roles;

namespace IdentityServer.Data.Services;

public class RoleMappingValidationService : IRoleMappingValidationService
{
    private readonly IStorage<ClientExt> _clientStorage;
    private readonly IEntraUserService _entraUserService;
    private readonly IEntraGroupService _entraGroupService;

    public RoleMappingValidationService(
        IStorage<ClientExt> clientStorage,
        IEntraUserService entraUserService,
        IEntraGroupService entraGroupService)
    {
        _clientStorage = clientStorage;
        _entraUserService = entraUserService;
        _entraGroupService = entraGroupService;
    }

    public async Task<OperationStatus> ValidateApiRoleMappingAsync(RoleMapping resource)
    {
        var status = new OperationStatus();

        if (string.IsNullOrWhiteSpace(resource.Value))
        {
            status.Errors.Add($"Role Mapping value cannot be empty or blank.");
            return status;
        }

        switch (resource.MappingType)
        {
            case RoleMapType.SecurityGroup:
                var resolvedGroup = await _entraGroupService.GetGroupByObjectIdAsync(resource.Value);
                var group = ValidateSecurityGroupMapping(resource.Value, resource.Description, resolvedGroup.Groups, status);
                resource.Description = group?.DisplayName;
                break;
            case RoleMapType.UserObjectId:
                var resolvedUser = await _entraUserService.GetUserByObjectIdAsync(resource.Value); // disabled users will produce warnings in validation
                var user = ValidateUserObjectIdMapping(resource.Value, resource.Description, resolvedUser.Users, status);
                resource.Description = user?.DisplayName;
                break;
            case RoleMapType.ClientId:
                var resolvedClients = await _clientStorage.ToListAsync(c => c.ClientId == resource.Value);
                var client = ValidateClientIdMapping(resource.Value, resource.Description, resolvedClients, status);
                resource.Description = client?.ClientName;
                break;
            default:
                status.Errors.Add($"Unknown mapping type: {resource.MappingType}");
                break;
        }

        return status;
    }

    public async Task<OperationStatus> ValidateClientRoleMappingAsync(ClientRoleMapping resource)
    {
        var status = new OperationStatus();

        if (string.IsNullOrWhiteSpace(resource.Value))
        {
            status.Errors.Add($"Role Mapping value cannot be empty or blank.");
            return status;
        }

        switch (resource.MappingType)
        {
            case ClientRoleMapType.SecurityGroup:
                var resolvedGroup = await _entraGroupService.GetGroupByObjectIdAsync(resource.Value);
                var group = ValidateSecurityGroupMapping(resource.Value, resource.Description, resolvedGroup.Groups, status);
                resource.Description = group?.DisplayName;
                break;
            case ClientRoleMapType.UserObjectId:
                var resolvedUser = await _entraUserService.GetUserByObjectIdAsync(resource.Value); // disabled users will produce warnings in validation
                var user = ValidateUserObjectIdMapping(resource.Value, resource.Description, resolvedUser.Users, status);
                resource.Description = user?.DisplayName;
                break;
            default:
                status.Errors.Add($"Unknown mapping type: {resource.MappingType}");
                break;
        }

        return status;
    }

    public async Task ValidateImportRoleMappingsAsync(List<RoleMappingValueObject> roleMappings, OperationStatus status)
    {
        var roleMappingsByType = roleMappings.GroupBy(r => r.MappingType);

        foreach (var roleMappingGroup in roleMappingsByType)
        {
            if (!Enum.TryParse<RoleMapType>(roleMappingGroup.Key, out var mappingType))
            {
                status.Errors.Add($"Invalid Role Mapping Type: {roleMappingGroup.Key}. Valid values are: {string.Join(", ", Enum.GetNames<RoleMapType>())}");
                continue;
            }

            IEnumerable<RoleMappingValueObject> mappings = roleMappingGroup;
            if (mappings.Any(r => string.IsNullOrWhiteSpace(r.Value)))
            {
                status.Errors.Add($"Role Mapping Type {roleMappingGroup.Key} contains empty or blank values.");
                mappings = mappings.Where(r => !string.IsNullOrWhiteSpace(r.Value)).ToList();
            }

            switch (mappingType)
            {
                case RoleMapType.SecurityGroup:
                    await ValidateSecurityGroupMappingsAsync(mappings, status);
                    break;
                case RoleMapType.UserObjectId:
                    await ValidateUserObjectIdMappingsAsync(mappings, status);
                    break;
                case RoleMapType.ClientId:
                    await ValidateClientIdMappingsAsync(mappings, status);
                    break;
                default:
                    status.Errors.Add($"Unknown mapping type: {mappingType}");
                    break;
            }
        }
    }

    private async Task ValidateClientIdMappingsAsync(IEnumerable<RoleMappingValueObject> mappings, OperationStatus status)
    {
        var clientIds = mappings.Select(m => m.Value).ToHashSet(StringComparer.OrdinalIgnoreCase);
        var resolvedClients = await _clientStorage.ToListAsync(c => clientIds.Contains(c.ClientId));

        foreach (var mapping in mappings)
        {
            var client = ValidateClientIdMapping(mapping.Value, mapping.Description, resolvedClients, status);
            mapping.Description = client?.ClientName;
        }
    }

    private static ClientExt? ValidateClientIdMapping(string value, string? description, List<ClientExt> resolvedClients, OperationStatus status)
    {
        var client = resolvedClients.FirstOrDefault(g => string.Equals(g.ClientId, value, StringComparison.OrdinalIgnoreCase));
        if (client == null)
        {
            status.Errors.Add($"Client with ClientId '{value}' does not exist.");
            return null;
        }

        if (string.IsNullOrWhiteSpace(client.ClientName))
        {
            status.Errors.Add($"Client with ClientId '{value}' has an empty name.");
            return null;
        }

        if (!string.IsNullOrWhiteSpace(description) && !string.Equals(description, client.ClientName, StringComparison.OrdinalIgnoreCase))
        {
            status.Warnings.Add($"Mapping with Client Id '{value}' description '{description}' does not match the client's display name '{client.ClientName}'.");
        }

        return client;
    }

    private async Task ValidateUserObjectIdMappingsAsync(IEnumerable<RoleMappingValueObject> mappings, OperationStatus status)
    {
        var resolvedUsers = await _entraUserService.GetUsersByObjectIdsAsync(mappings.Select(m => m.Value)); // disabled users will produce warnings in validation

        foreach (var mapping in mappings)
        {
            var user = ValidateUserObjectIdMapping(mapping.Value, mapping.Description, resolvedUsers.Users, status);
            mapping.Description = user?.DisplayName;
        }
    }

    private static User? ValidateUserObjectIdMapping(string value, string? description, List<User> resolvedUsers, OperationStatus status)
    {
        var user = resolvedUsers.FirstOrDefault(g => string.Equals(g.OId, value, StringComparison.OrdinalIgnoreCase));
        if (user == null)
        {
            status.Errors.Add($"User with ObjectId '{value}' does not exist in Entra ID.");
            return null;
        }

        if (string.IsNullOrWhiteSpace(user.DisplayName))
        {
            status.Errors.Add($"User with ObjectId '{value}' has no display name in Entra ID.");
            return null;
        }

        if (user.AccountEnabled != true)
        {
            status.Warnings.Add($"User ObjectId '{value}' account is disabled in Entra ID.");
        }

        if (!string.Equals(description, user.DisplayName, StringComparison.OrdinalIgnoreCase))
        {
            status.Warnings.Add($"User ObjectId '{value}' description '{description}' does not match the user's display name '{user.DisplayName}'.");
        }

        return user;
    }

    private async Task ValidateSecurityGroupMappingsAsync(IEnumerable<RoleMappingValueObject> mappings, OperationStatus status)
    {
        var resolvedGroups = await _entraGroupService.GetGroupsByObjectIdsAsync(mappings.Select(m => m.Value));

        foreach (var mapping in mappings)
        {
            var group = ValidateSecurityGroupMapping(mapping.Value, mapping.Description, resolvedGroups.Groups, status);
            mapping.Description = group?.DisplayName;
        }
    }

    private static Group? ValidateSecurityGroupMapping(string value, string? description, List<Group> resolvedGroups, OperationStatus status)
    {
        var group = resolvedGroups.FirstOrDefault(g => string.Equals(g.Id, value, StringComparison.OrdinalIgnoreCase));
        if (group == null)
        {
            status.Errors.Add($"Group with ObjectId '{value}' does not exist in Entra ID.");
            return null;
        }

        if (string.IsNullOrWhiteSpace(group.DisplayName))
        {
            status.Errors.Add($"Group with ObjectId '{value}' has no display name in Entra ID.");
            return null;
        }

        if (!string.Equals(description, group.DisplayName, StringComparison.OrdinalIgnoreCase))
        {
            status.Warnings.Add($"Group ObjectId '{value}' description '{description}' does not match the group's display name '{group.DisplayName}'.");
        }

        return group;
    }
}
