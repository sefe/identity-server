using System.Security.Claims;
using System.Text.Json;
using Microsoft.Extensions.DependencyInjection;
using NSubstitute;
using IdentityServer.Abstraction.Configs;
using IdentityServer.Abstraction.Contracts;
using IdentityServer.Abstraction.Contracts.MicrosoftGraph;
using IdentityServer.Abstraction.Entities.EntraEntities;
using IdentityServer.Abstraction.Entities.IdentityServerConfig.SystemPermissions;
using IdentityServer.Abstraction.Extensions;
using IdentityServer.Tests.Common;

namespace IdentityServer.AdminPortal.Test;

public class SystemPermissionUtility
{
    public readonly IEntraUserService EntraUserServiceMock = Substitute.For<IEntraUserService>();

    public readonly string[] DefaultEnvironments = new[] { SystemPermissionEnvironmentNames.Development };
    public readonly string[] StandardEnvironments = new[] { SystemPermissionEnvironmentNames.Development, SystemPermissionEnvironmentNames.Production };

    private IStorage<SystemPermission> _permissionsRepo;
    private IStorage<SystemPermissionEnvironment> _envsRepo;
    private IStorage<SystemPermissionRole> _rolesRepo;

    private readonly IAuthConfig _groupMembershipConfig = Substitute.For<IAuthConfig>();
    private readonly string _membershipReadersGroupId;
    private readonly string _membershipContributorsGroupId;
    private readonly List<Group> _readerResponse;
    private readonly List<Group> _contributorResponse;

    private readonly JsonSerializerOptions _jsonSerializerOptions = new()
    {
        ReferenceHandler = System.Text.Json.Serialization.ReferenceHandler.IgnoreCycles
    };

    public SystemPermissionUtility()
    {
        _membershipReadersGroupId = Guid.NewGuid().ToString();
        _membershipContributorsGroupId = Guid.NewGuid().ToString();
        _readerResponse = new()
        {
            new() { Id = _membershipReadersGroupId, DisplayName = "Admin UI Readers" }
        };
        _contributorResponse = new()
        {
            new() { Id = _membershipReadersGroupId, DisplayName = "Admin UI Readers" },
            new() { Id = _membershipContributorsGroupId, DisplayName = "Admin UI Users" },
        };
    }

    public Action<ServiceCollection> AddToServiceCollection => sc =>
    {
        sc.ReplaceWithInstance(EntraUserServiceMock);
        sc.ReplaceWithInstance(_groupMembershipConfig);
    };

    public IServiceProvider Setup(IServiceProvider provider)
    {
        _groupMembershipConfig.ReaderGroupId.Returns(_membershipReadersGroupId);
        _groupMembershipConfig.ContributorGroupId.Returns(_membershipContributorsGroupId);

        EntraUserServiceMock.GetUserMembershipInGroups(Arg.Any<string>(), Arg.Any<IEnumerable<string>>()).Returns(call =>
        {
            var objectId = call.Arg<string>();
            if (!string.IsNullOrEmpty(objectId) && _userGroupMapping.TryGetValue(objectId, out var response))
            {
                return response;
            }
            else
            {
                return null;
            }
        });

        AddUserToContributorsGroup(TestUser.SuperUser.GetUserObjectId());
        AddUserToContributorsGroup(TestUser.Admin.GetUserObjectId());
        AddUserToContributorsGroup(TestUser.Contributor.GetUserObjectId());
        AddUserToReadersGroup(TestUser.Reader.GetUserObjectId());

        _permissionsRepo = provider.GetRequiredService<IStorage<SystemPermission>>();
        _rolesRepo = provider.GetRequiredService<IStorage<SystemPermissionRole>>();
        _envsRepo = provider.GetRequiredService<IStorage<SystemPermissionEnvironment>>();
        return provider;
    }

    private readonly Dictionary<string, List<Group>> _userGroupMapping = new();

    public void AddUserToReadersGroup(string userObjectId)
    {
        _userGroupMapping[userObjectId] = _readerResponse;
    }

    public void AddUserToContributorsGroup(string userObjectId)
    {
        _userGroupMapping[userObjectId] = _contributorResponse;
    }

    public static SystemPermission GetNewSystemPermission()
    {
        return new SystemPermission
        {
            Id = 0,
            Name = Guid.NewGuid().ToString(),
            Description = "Unit testing permission",
        };
    }

    private static SystemPermissionRole GetNewPermissionRole(ClaimsPrincipal user, SystemPermissionRoleType role, SystemPermissionEnvironment env)
    {
        return new SystemPermissionRole
        {
            Id = 0,
            Name = user.Identity.Name,
            OId = user.FindFirstValue("oid"),
            RoleType = role,
            SystemPermissionEnvironmentId = env.Id
        };
    }

    public async Task<SystemPermission> CreatePermission(ClaimsPrincipal user, SystemPermission permission, string[] envs)
    {
        var addedPermission = await _permissionsRepo.AddAsync(permission);
        foreach (var e in envs)
        {
            var eToAdd = new SystemPermissionEnvironment { Id = 0, Environment = e, SystemPermissionId = addedPermission.Id, SystemPermission = addedPermission };
            var addedEnv = await _envsRepo.AddAsync(eToAdd);
            // the creator must be added as Writer
            var pToAdd = GetNewPermissionRole(user, SystemPermissionRoleType.Writer, addedEnv);
            await _rolesRepo.AddAsync(pToAdd);
        }
        return JsonSerializer.Deserialize<SystemPermission>(JsonSerializer.Serialize(await _permissionsRepo.GetByIdAsync(addedPermission.Id), _jsonSerializerOptions));
    }

    public async Task<SystemPermission> AssignPermissionToUser(ClaimsPrincipal user, SystemPermission permission, string environment, SystemPermissionRoleType role)
    {
        foreach (var env in permission.Environments.Where(e => e.Environment == environment))
        {
            var toAdd = GetNewPermissionRole(user, role, env);
            await _rolesRepo.AddAsync(toAdd);
        }
        return JsonSerializer.Deserialize<SystemPermission>(JsonSerializer.Serialize(await _permissionsRepo.GetByIdAsync(permission.Id), _jsonSerializerOptions));
    }
}
