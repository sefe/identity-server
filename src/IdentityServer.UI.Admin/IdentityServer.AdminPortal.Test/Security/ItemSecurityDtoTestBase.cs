// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

using System.Security.Claims;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Extensions.DependencyInjection;
using IdentityServer.Abstraction.Contracts;
using IdentityServer.Abstraction.DTO;
using IdentityServer.Abstraction.Entities.IdentityServerConfig.SystemPermissions;
using IdentityServer.Abstraction.Exceptions;

namespace IdentityServer.AdminPortal.Test.Security;
public abstract class ItemSecurityDtoTestBase<TController, TItem, TCreateItem, TListItem> : PermissionSecurityTestBase
    where TController : ControllerBase
    where TItem : IDtoRead, IHasEnvironment
    where TListItem : IDtoRead, IHasEnvironment
    where TCreateItem : IDtoCreate
{
    protected TItem item1;
    protected TItem item2;

    protected TController _controller;

    protected abstract Func<int, TCreateItem> GetDefaultItem { get; }
    protected abstract Task<TItem> CreateFunc(TController controller, TCreateItem item, ClaimsPrincipal user);
    protected abstract Task<TItem> CloneFunc(TController controller, int id, int targetEnvId, ClaimsPrincipal user);
    protected abstract Task<List<TListItem>> GetAllFunc(TController controller, ClaimsPrincipal user);
    protected abstract Task<TItem> GetFunc(TController controller, int id, ClaimsPrincipal user);
    protected abstract Task<TItem> UpdateFunc(TController controller, int id, ClaimsPrincipal user);
    protected abstract Task<int?> DeleteFunc(TController controller, int id, ClaimsPrincipal user);

    [SetUp]
    public void Setup()
    {
        var provider = base.Setup(sc =>
        {
            sc.AddScoped<TController>();
        });

        _controller = provider.GetRequiredService<TController>();
    }

    protected Task<TItem> CreateItem(ClaimsPrincipal user, TCreateItem item)
    {
        return CreateFunc(_controller, item, user);
    }

    protected async Task CreateDefaultItemInfrastructure()
    {
        await CreateDefaultPermissionInfrastructure();
        item1 = await CreateItem(SuperUser, GetDefaultItem(_permission1.Environments[0].Id));
        item2 = await CreateItem(SuperUser, GetDefaultItem(_permission2.Environments[0].Id));
    }

    protected async Task CreateDefaultInfrastructure_With1Permission_And2Environments()
    {
        await CreateDefaultPermissionInfrastructure_With1Permission_And2Environments();
        item1 = await CreateItem(SuperUser, GetDefaultItem(_permission1.Environments[0].Id));
        item2 = await CreateItem(SuperUser, GetDefaultItem(_permission1.Environments[1].Id));
    }

    [Test]
    public async Task Reader_Cannot_Read_Unassigned()
    {
        // Arrange
        await CreateDefaultItemInfrastructure();

        // do not assign any permissions

        // Act
        Assert.ThrowsAsync<EntityAccessException>(() => GetFunc(_controller, item1.Id, Reader));
        Assert.ThrowsAsync<EntityAccessException>(() => GetFunc(_controller, item2.Id, Reader));
    }

    [Test]
    public async Task Reader_Can_Read_Assigned()
    {
        // Arrange
        await CreateDefaultItemInfrastructure();

        _permission1 = await AssignPermissionToUser(Reader, _permission1, _permission1.Environments[0].Environment, SystemPermissionRoleType.Reader);

        // Act
        var result1 = await GetFunc(_controller, item1.Id, Reader);
        Assert.ThrowsAsync<EntityAccessException>(() => GetFunc(_controller, item2.Id, Reader));

        // Assert
        Assert.That(result1, Is.Not.Null);
    }

    [Test]
    public async Task Reader_Cannot_Create()
    {
        // Arrange
        await CreateDefaultItemInfrastructure();

        var newItem = GetDefaultItem(_permission1.Environments[0].Id);

        _permission1 = await AssignPermissionToUser(Reader, _permission1, _permission1.Environments[0].Environment, SystemPermissionRoleType.Reader);

        // Act
        Assert.ThrowsAsync<EntityAccessException>(() => CreateFunc(_controller, newItem, Reader));
    }

    [Test]
    public async Task Reader_Cannot_Update()
    {
        // Arrange
        await CreateDefaultItemInfrastructure();

        _permission1 = await AssignPermissionToUser(Reader, _permission1, _permission1.Environments[0].Environment, SystemPermissionRoleType.Reader);

        // Act
        Assert.ThrowsAsync<EntityAccessException>(() => UpdateFunc(_controller, item1.Id, Reader));
    }

    [Test]
    public async Task Reader_Cannot_Delete()
    {
        // Arrange
        await CreateDefaultItemInfrastructure();

        _permission1 = await AssignPermissionToUser(Reader, _permission1, _permission1.Environments[0].Environment, SystemPermissionRoleType.Reader);

        // Act
        Assert.ThrowsAsync<EntityAccessException>(() => DeleteFunc(_controller, item1.Id, Reader));
    }

    [Test]
    public async Task Reader_Can_ReadAll_DifferentPermissions()
    {
        // Arrange
        var user = Reader;

        await CreateDefaultItemInfrastructure();

        _permission1 = await AssignPermissionToUser(user, _permission1, _permission1.Environments[0].Environment, SystemPermissionRoleType.Reader);

        // Act
        var result = await GetAllFunc(_controller, user);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result, Has.Count.EqualTo(2));
            Assert.That(result.Any(_ => _.Id == item1.Id && _.AccessLevel == SystemPermissionRoleType.Reader), Is.True);
            Assert.That(result.Any(_ => _.Id == item2.Id && _.AccessLevel == SystemPermissionRoleType.None), Is.True);
        }
    }

    [Test]
    public async Task Reader_Can_ReadAll_DifferentEnvironments()
    {
        // Arrange
        var user = Reader;

        await CreateDefaultInfrastructure_With1Permission_And2Environments();

        _permission1 = await AssignPermissionToUser(user, _permission1, _permission1.Environments[0].Environment, SystemPermissionRoleType.Reader);

        // Act
        var result = await GetAllFunc(_controller, user);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result, Has.Count.EqualTo(2));
            Assert.That(result.Any(_ => _.Id == item1.Id && _.AccessLevel == SystemPermissionRoleType.Reader), Is.True);
            Assert.That(result.Any(_ => _.Id == item2.Id && _.AccessLevel == SystemPermissionRoleType.None), Is.True);
        }
    }

    [Test]
    [TestCase(SystemPermissionRoleType.Reader)]
    [TestCase(SystemPermissionRoleType.Writer)]
    public async Task Contributor_Can_ReadAll_DifferentPermissions(SystemPermissionRoleType permissionType)
    {
        // Arrange
        var user = Contributor;

        await CreateDefaultItemInfrastructure();

        _permission1 = await AssignPermissionToUser(user, _permission1, _permission1.Environments[0].Environment, permissionType);

        // Act
        var result = await GetAllFunc(_controller, user);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result, Has.Count.EqualTo(2));
            Assert.That(result.Any(_ => _.Id == item1.Id && _.AccessLevel == SystemPermissionRoleType.Reader), Is.True);
            Assert.That(result.Any(_ => _.Id == item2.Id && _.AccessLevel == SystemPermissionRoleType.None), Is.True);
        }
    }

    [Test]
    [TestCase(SystemPermissionRoleType.Reader)]
    [TestCase(SystemPermissionRoleType.Writer)]
    public async Task Contributor_Can_ReadAll_DifferentEnvironments(SystemPermissionRoleType permissionType)
    {
        // Arrange
        var user = Contributor;

        await CreateDefaultInfrastructure_With1Permission_And2Environments();

        _permission1 = await AssignPermissionToUser(user, _permission1, _permission1.Environments[0].Environment, permissionType);

        // Act
        var result = await GetAllFunc(_controller, user);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result, Has.Count.EqualTo(2));
            Assert.That(result.Any(_ => _.Id == item1.Id && _.AccessLevel == SystemPermissionRoleType.Reader), Is.True);
            Assert.That(result.Any(_ => _.Id == item2.Id && _.AccessLevel == SystemPermissionRoleType.None), Is.True);
        }
    }

    [Test]
    public async Task Contributor_Reader_Cannot_Create()
    {
        // Arrange
        await CreateDefaultItemInfrastructure();

        var newItem = GetDefaultItem(_permission1.Environments[0].Id);

        _permission1 = await AssignPermissionToUser(Contributor, _permission1, _permission1.Environments[0].Environment, SystemPermissionRoleType.Reader);

        // Act
        Assert.ThrowsAsync<EntityAccessException>(() => CreateFunc(_controller, newItem, Contributor));
    }

    [Test]
    public async Task Contributor_Writer_Can_Create()
    {
        // Arrange
        await CreateDefaultItemInfrastructure();

        var newItem = GetDefaultItem(_permission1.Environments[0].Id);

        _permission1 = await AssignPermissionToUser(Contributor, _permission1, _permission1.Environments[0].Environment, SystemPermissionRoleType.Writer);

        // Act
        var result1 = await CreateFunc(_controller, newItem, Contributor);

        // Assert
        Assert.That(result1, Is.Not.Null);
    }

    [Test]
    public async Task Contributor_Reader_Cannot_Update()
    {
        // Arrange
        await CreateDefaultItemInfrastructure();

        _permission1 = await AssignPermissionToUser(Contributor, _permission1, _permission1.Environments[0].Environment, SystemPermissionRoleType.Reader);

        // Act
        Assert.ThrowsAsync<EntityAccessException>(() => UpdateFunc(_controller, item1.Id, Contributor));
    }

    [Test]
    public async Task Contributor_Writer_Can_Update()
    {
        // Arrange
        await CreateDefaultItemInfrastructure();

        _permission1 = await AssignPermissionToUser(Contributor, _permission1, _permission1.Environments[0].Environment, SystemPermissionRoleType.Writer);

        // Act
        var result1 = await UpdateFunc(_controller, item1.Id, Contributor);

        // Assert
        Assert.That(result1.Id, Is.EqualTo(item1.Id));
    }

    [Test]
    public async Task Contributor_Reader_Cannot_Delete()
    {
        // Arrange
        await CreateDefaultItemInfrastructure();

        _permission1 = await AssignPermissionToUser(Contributor, _permission1, _permission1.Environments[0].Environment, SystemPermissionRoleType.Reader);

        // Act
        Assert.ThrowsAsync<EntityAccessException>(() => DeleteFunc(_controller, item1.Id, Contributor));
    }

    [Test]
    public async Task Contributor_Writer_Can_Delete()
    {
        // Arrange
        await CreateDefaultItemInfrastructure();

        _permission1 = await AssignPermissionToUser(Contributor, _permission1, _permission1.Environments[0].Environment, SystemPermissionRoleType.Writer);

        // Act
        var result1 = await DeleteFunc(_controller, item1.Id, Contributor);

        // Assert
        Assert.That(result1, Is.EqualTo(item1.Id));
    }

    [Test]
    public async Task Admin_Can_Read_Without_Assignments()
    {
        // Arrange
        await CreateDefaultItemInfrastructure();
        var result1 = await GetAllFunc(_controller, Admin);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result1, Has.Count.EqualTo(2));
            Assert.That(result1[0].Id, Is.EqualTo(item1.Id));
            Assert.That(result1[1].Id, Is.EqualTo(item2.Id));
        }
    }

    [Test]
    public async Task Admin_Can_Create_Without_Assignments()
    {
        // Arrange
        await CreateDefaultItemInfrastructure();

        var newItem = GetDefaultItem(_permission1.Environments[0].Id);

        // assign no permissions

        // Act
        var result1 = await CreateFunc(_controller, newItem, Admin);

        // Assert
        Assert.That(result1, Is.Not.Null);
    }

    [Test]
    public async Task Admin_Can_Update_Without_Assignments()
    {
        // Arrange
        await CreateDefaultItemInfrastructure();

        // assign no permissions

        // Act
        var result1 = await UpdateFunc(_controller, item1.Id, Admin);

        // Assert
        Assert.That(result1.Id, Is.EqualTo(item1.Id));
    }

    [Test]
    public async Task Admin_Can_Delete_Without_Assignments()
    {
        // Arrange
        await CreateDefaultItemInfrastructure();

        // assign no permissions

        // Act
        var result1 = await DeleteFunc(_controller, item1.Id, Admin);

        // Assert
        Assert.That(result1.Value, Is.EqualTo(item1.Id));
    }

    [Test]
    public async Task Clone_Reader_Assignment_To_Source_Missing()
    {
        // Arrange
        await CreateDefaultInfrastructure_With1Permission_And2Environments();

        // assign no reader permissions

        // Act
        Assert.ThrowsAsync<EntityAccessException>(() => CloneFunc(_controller, item1.Id, _permission1.Environments[1].Id, Contributor));
    }

    [Test]
    public async Task Clone_Writer_Assignment_To_Target_Missing()
    {
        // Arrange
        await CreateDefaultInfrastructure_With1Permission_And2Environments();

        _permission1 = await AssignPermissionToUser(Contributor, _permission1, _permission1.Environments[0].Environment, SystemPermissionRoleType.Reader);
        _permission1 = await AssignPermissionToUser(Contributor, _permission1, _permission1.Environments[1].Environment, SystemPermissionRoleType.Reader);
        // assign no writer permissions

        // Act
        Assert.ThrowsAsync<EntityAccessException>(() => CloneFunc(_controller, item1.Id, _permission1.Environments[1].Id, Contributor));
    }

    [Test]
    public async Task Admin_Can_Clone_Without_Assignments()
    {
        // Arrange
        await CreateDefaultInfrastructure_With1Permission_And2Environments();

        // assign no permissions

        // Act
        var result1 = await CloneFunc(_controller, item1.Id, _permission1.Environments[1].Id, Admin);

        // Assert
        Assert.That(result1.Id, Is.Not.EqualTo(item1.Id));
    }

}
