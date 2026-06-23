// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

using Microsoft.Extensions.DependencyInjection;
using NSubstitute;
using IdentityServer.Abstraction.Contracts.MicrosoftGraph;
using IdentityServer.Abstraction.Entities.EntraEntities;
using IdentityServer.Abstraction.Entities.IdentityServerConfig;
using IdentityServer.Abstraction.Entities.IdentityServerConfig.SystemPermissions;
using IdentityServer.AdminPortal.Server.Controllers;
using IdentityServer.AdminPortal.Test.Controller;
using IdentityServer.AdminPortal.Test.Extensions;

namespace IdentityServer.AdminPortal.Test.Security;

public class ApiResourceRoleMappingControllerSecurityTests : ControllerTestBase
{
    private readonly SystemPermissionUtility _permissionUtil = new();
    private ApiResourceController _apiResourceController;
    private ApiResourcePropertyRoleController _apiResourceRoleController;
    private ApiResourcePropertyRoleMappingController _apiResourceRoleMappingController;
    private readonly IEntraGroupService _entraGroupService = Substitute.For<IEntraGroupService>();
    private readonly IEntraUserService _entraUserService = Substitute.For<IEntraUserService>();

    [SetUp]
    public void Setup()
    {
        var provider = IoC.GetProvider(sc =>
        {
            _permissionUtil.AddToServiceCollection(sc);
            sc.AddScoped<ApiResourceController>();
            sc.AddScoped<ApiResourcePropertyRoleController>();
            sc.AddScoped<ApiResourcePropertyRoleMappingController>();

            sc.AddSingleton(_entraGroupService);
            sc.AddSingleton(_entraUserService);
        });

        _permissionUtil.Setup(provider);

        _apiResourceController = provider.GetRequiredService<ApiResourceController>();
        _apiResourceRoleController = provider.GetRequiredService<ApiResourcePropertyRoleController>();
        _apiResourceRoleMappingController = provider.GetRequiredService<ApiResourcePropertyRoleMappingController>();
    }

    [Test]
    public async Task User_Can_Create_GroupRoleMapping()
    {
        // Arrange
        var groupObjectId = Guid.NewGuid().ToString();
        var groupDisplayName = Guid.NewGuid().ToString();
        _entraGroupService.GetGroupByObjectIdAsync(Arg.Any<string>()).Returns(new GroupResponse { Groups = new() { new Group { Id = groupObjectId, DisplayName = groupDisplayName } } });
        // User 1 - Writer of env1
        // permission 1 - env1 - api 1 - role 1 - rolemapping (group)
        var sp = await _permissionUtil.CreatePermission(SuperUser, SystemPermissionUtility.GetNewSystemPermission(), _permissionUtil.DefaultEnvironments);
        sp = await _permissionUtil.AssignPermissionToUser(Contributor, sp, SystemPermissionEnvironmentNames.Development, SystemPermissionRoleType.Writer);
        var api = await _apiResourceController.Call_CreateApiResourceAsync(ApiResourceControllerExtensions.GetDefaultApiResource(sp.Environments.First().Id), Contributor);
        var role = await _apiResourceRoleController.Call_AddApiResourceRoleAsync(ApiResourceRoleControllerExtensions.NewRoleFor(api.Id, "TestRole"), Contributor);
        var roleMapping = ApiResourceRoleMappingControllerExtensions.NewRoleMappingFor(api.Id, role.Id, RoleMapType.SecurityGroup, groupObjectId);

        // Act
        var addedRoleMapping = await _apiResourceRoleMappingController.Call_AddApiResourceRoleMappingAsync(roleMapping, Contributor);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(addedRoleMapping.ApiResourceRoleId, Is.EqualTo(role.Id));
            Assert.That(addedRoleMapping.MappingType, Is.EqualTo(roleMapping.MappingType));
            Assert.That(addedRoleMapping.Description, Is.EqualTo(groupDisplayName));
            Assert.That(addedRoleMapping.Value, Is.EqualTo(roleMapping.Value));
        }
    }
}
