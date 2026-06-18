using System.Security.Claims;
using AutoMapper;
using IdentityServer.Abstraction.Contracts;
using IdentityServer.Abstraction.Contracts.MicrosoftGraph;
using IdentityServer.Abstraction.DTO.SystemPermissions;
using IdentityServer.Abstraction.Entities.IdentityServerConfig.SystemPermissions;
using IdentityServer.Abstraction.Exceptions;

namespace IdentityServer.Data.Repositories.DtoRepositories;

/// <summary>
/// Responsible for DTO mapping and access security checks for <seealso cref="SystemPermissionRole"/> entities.
/// </summary>
internal class SystemPermissionRoleDtoRepository :
    IDtoCreateRepository<SystemPermissionRoleDtoRead, SystemPermissionRoleDtoCreate>,
    IDtoUpdateRepository<SystemPermissionRoleDtoRead, SystemPermissionRoleDtoUpdate>,
    IDtoParentListRepository<SystemPermissionRoleDtoRead>
{
    private readonly IStorage<SystemPermissionRole> _roleStorage;
    private readonly IStorage<SystemPermissionEnvironment> _envStorage;
    private readonly IMapper _mapper;
    private readonly IPermissionChecker _permissionChecker;
    private readonly IEntraUserService _entraUserService;
    private readonly IUserGroupMembershipService _entraUserMembership;

    public SystemPermissionRoleDtoRepository(
        IStorage<SystemPermissionRole> roleStorage,
        IStorage<SystemPermissionEnvironment> envStorage,
        IMapper mapper,
        IPermissionChecker permissionChecker,
        IEntraUserService entraUserService,
        IUserGroupMembershipService entraUserMembership)
    {
        _roleStorage = roleStorage;
        _envStorage = envStorage;
        _mapper = mapper;
        _permissionChecker = permissionChecker;
        _entraUserService = entraUserService;
        _entraUserMembership = entraUserMembership;
    }

    public async Task<SystemPermissionRoleDtoRead> CreateAsync(ClaimsPrincipal user, SystemPermissionRoleDtoCreate resource)
    {
        if (null == await _envStorage.GetByIdAsync(resource.SystemPermissionEnvironmentId))
        {
            throw new EntityReferenceException($"System Permission Environment ID '{resource.SystemPermissionEnvironmentId}' doesn't exist.");
        }

        await _permissionChecker.GetAccessRoleOrThrowIfNoAccessToEnvAsync(user, resource.SystemPermissionEnvironmentId, EntityAccessType.Create, $"System Permission Environment '{resource.SystemPermissionEnvironmentId}'");

        var existing = await _roleStorage.FirstOrDefaultAsync(r => r.SystemPermissionEnvironmentId == resource.SystemPermissionEnvironmentId && r.OId == resource.OId);
        if (existing != null)
        {
            throw new EntityAlreadyExistsException($"'{existing.RoleType}' System Permission Role for '{existing.Name}' already exists.");
        }

        var toBeCreated = _mapper.Map<SystemPermissionRole>(resource);

        toBeCreated.Name = await GetUserDisplayNameAsync(toBeCreated.OId);

        // only allow to add Readers from Reader and Writer groups, Writers only from Writers group
        switch (resource.RoleType)
        {
            case SystemPermissionRoleType.Reader:
                if (!await _entraUserMembership.IsReaderOrContributorAsync(resource.OId))
                {
                    throw new UserInsufficientRoleException($"User ID '{resource.OId}' is not a member of Reader or Contributor Entra Groups and thus cannot be assigned.");
                }

                break;
            case SystemPermissionRoleType.Writer:
                if (!await _entraUserMembership.IsContributorAsync(resource.OId))
                {
                    throw new UserInsufficientRoleException($"User ID '{resource.OId}' is not a member of Contributor Entra Group and thus cannot be assigned.");
                }

                break;
            default:
                throw new InvalidOperationException($"Unsupported role '{resource.RoleType}'.");
        }

        var storedItem = await _roleStorage.AddAsync(toBeCreated);
        return _mapper.Map<SystemPermissionRoleDtoRead>(storedItem);
    }

    public async Task<int?> DeleteAsync(ClaimsPrincipal user, int id)
    {
        var existing = await _roleStorage.GetByIdAsync(id);
        if (existing == null)
        {
            return null;
        }

        await _permissionChecker.GetAccessRoleOrThrowIfNoAccessToEnvAsync(user, existing.SystemPermissionEnvironmentId, EntityAccessType.Delete, existing.ToString());

        if (existing.RoleType == SystemPermissionRoleType.Writer)
        {
            var otherWritersAssigned = await _roleStorage.AnyAsync(r => r.SystemPermissionEnvironmentId == existing.SystemPermissionEnvironmentId
                && r.RoleType == SystemPermissionRoleType.Writer
                && r.OId != existing.OId);
            if (!otherWritersAssigned)
            {
                throw new EntityReferenceException($"Cannot delete the last Writer role from System Permission Environment '{existing.SystemPermissionEnvironmentId}'.");
            }

            var env = await _envStorage.GetByIdAsync(existing.SystemPermissionEnvironmentId)
                                        ?? throw new EntityReferenceException($"System Permission Environment ID '{existing.SystemPermissionEnvironmentId}' doesn't exist.");
            if (UserCanEditAllEnvironments(env.SystemPermission, existing.OId) && CountUsersWhoCanEditAllEnvironments(env.SystemPermission) == 1)
            {
                throw new EntityReferenceException($"Cannot delete the last Full Writer role from System Permission '{env.SystemPermission.Name}'.");
            }
        }

        // 2-step approach to capture who deleted the role
        existing.Updated = DateTime.UtcNow;
        await _roleStorage.UpdateAsync(existing);
        return await _roleStorage.DeleteAsync(existing);
    }

    public async Task<IEnumerable<SystemPermissionRoleDtoRead>> GetAllByParentIdAsync(ClaimsPrincipal user, int parentId)
    {
        await _permissionChecker.GetAccessRoleOrThrowIfNoAccessToEnvAsync(user, parentId, EntityAccessType.Read, $"System Permission Environment '{parentId}'");

        var existing = await _roleStorage.ToListAsync(r => r.SystemPermissionEnvironmentId == parentId);

        return _mapper.Map<List<SystemPermissionRoleDtoRead>>(existing);
    }

    public async Task<SystemPermissionRoleDtoRead> UpdateAsync(ClaimsPrincipal user, SystemPermissionRoleDtoUpdate resource)
    {
        var entity = await _roleStorage.GetByIdAsync(resource.Id) ?? throw new EntityReferenceException($"System Permission Role '{resource.Id}' doesn't exist!");

        await _permissionChecker.GetAccessRoleOrThrowIfNoAccessToEnvAsync(user, entity.SystemPermissionEnvironmentId, EntityAccessType.Update, entity.ToString());

        // the only field that can be updated is RoleType
        entity.RoleType = resource.RoleType;

        var storedItem = await _roleStorage.UpdateAsync(entity);
        return _mapper.Map<SystemPermissionRoleDtoRead>(storedItem);
    }

    private async Task<string> GetUserDisplayNameAsync(string userObjectId)
    {
        var foundUser = await _entraUserService.GetUserByObjectIdAsync(userObjectId); // fine with disabled users
        if (foundUser.Users.Count == 0)
        {
            throw new EntityReferenceException($"No users found by the provided object Id '{userObjectId}'.");
        }

        return foundUser.Users[0].DisplayName;
    }

    private static bool UserCanEditAllEnvironments(SystemPermission systemPermission, string userObjectId)
    {
        return systemPermission?.Environments == null || systemPermission.Environments.Count == 0 || systemPermission.Environments.Where(e => e.Permissions.Count > 0)
            .All(spe => spe.Permissions.Any(p => p.OId == userObjectId && p.RoleType == SystemPermissionRoleType.Writer));
    }

    private static int CountUsersWhoCanEditAllEnvironments(SystemPermission systemPermission)
    {
        if (systemPermission?.Environments == null || systemPermission.Environments.Count == 0)
        {
            return 0;
        }

        return systemPermission.Environments
            .Where(e => e?.Permissions != null)
            .SelectMany(e => e.Permissions)
            .Where(p => p.RoleType == SystemPermissionRoleType.Writer)
            .GroupBy(p => p.OId)
            .Count(g => g.Count() == systemPermission.Environments.Count);
    }
}
