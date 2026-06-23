// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

using System.Security.Claims;
using Microsoft.Extensions.DependencyInjection;
using NSubstitute;
using IdentityServer.Abstraction.Entities.EntraEntities;
using IdentityServer.Abstraction.Entities.IdentityServerConfig.SystemPermissions;
using IdentityServer.AdminPortal.Test.Controller;
using IdentityServer.Tests.Common;

namespace IdentityServer.AdminPortal.Test.Security;

public abstract class PermissionSecurityTestBase : ControllerTestBase
{
    protected SystemPermissionUtility _permissionUtil = new();

    protected SystemPermission _permission1;
    protected SystemPermission _permission2;

    protected virtual IServiceProvider Setup(Action<ServiceCollection> configureServiceCollection)
    {
        var provider = IoC.GetProvider(sc =>
        {
            _permissionUtil.AddToServiceCollection(sc);
            configureServiceCollection(sc);
        });

        _permissionUtil.Setup(provider);

        return provider;
    }

    protected Task<SystemPermission> CreatePermission(ClaimsPrincipal user, SystemPermission permission, string[] envs)
    {
        return _permissionUtil.CreatePermission(user, permission, envs);
    }

    protected Task<SystemPermission> AssignPermissionToUser(ClaimsPrincipal user, SystemPermission permission, string environment, SystemPermissionRoleType role)
    {
        return _permissionUtil.AssignPermissionToUser(user, permission, environment, role);
    }

    protected async Task CreateDefaultPermissionInfrastructure()
    {
        _permission1 = await CreatePermission(TestUser.SuperUser, SystemPermissionUtility.GetNewSystemPermission(), _permissionUtil.DefaultEnvironments);
        _permission2 = await CreatePermission(TestUser.SuperUser, SystemPermissionUtility.GetNewSystemPermission(), _permissionUtil.DefaultEnvironments);
    }

    protected async Task CreateDefaultPermissionInfrastructure_With1Permission_And2Environments()
    {
        _permission1 = await CreatePermission(TestUser.SuperUser, SystemPermissionUtility.GetNewSystemPermission(), _permissionUtil.StandardEnvironments);
    }

    protected User CreateRandomReaderUser()
    {
        var temp = Guid.NewGuid().ToString();
        var expectedUser = new User { OId = $"some oid {temp}", DisplayName = $"some display name {temp}" };
        _permissionUtil.EntraUserServiceMock.GetUserByObjectIdAsync(expectedUser.OId).Returns(Task.FromResult(new UserResponse { Users = [expectedUser] }));
        _permissionUtil.AddUserToReadersGroup(expectedUser.OId);
        return expectedUser;
    }
}
