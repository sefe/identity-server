// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

using NSubstitute;
using IdentityServer.Abstraction.Contracts;
using IdentityServer.Abstraction.Contracts.MicrosoftGraph;
using IdentityServer.Abstraction.DTO.Export;
using IdentityServer.Abstraction.DTO.Import;
using IdentityServer.Abstraction.Entities.EntraEntities;
using IdentityServer.Abstraction.Entities.IdentityServerConfig;
using IdentityServer.Abstraction.Entities.IdentityServerConfig.SystemPermissions;
using IdentityServer.Data.DuendeEntityExtensions;
using IdentityServer.Data.Services;

namespace IdentityServer.Data.Test.Services;

[TestFixture]
public class RoleMappingValidationService_ValidateImportRoleMappingsAsync_Tests
{
    private IStorage<ClientExt> _clientStorage;
    private IEntraUserService _entraUserService;
    private IEntraGroupService _entraGroupService;
    private RoleMappingValidationService _service;

    [SetUp]
    public void SetUp()
    {
        _clientStorage = Substitute.For<IStorage<ClientExt>>();
        _entraUserService = Substitute.For<IEntraUserService>();
        _entraGroupService = Substitute.For<IEntraGroupService>();
        _service = new RoleMappingValidationService(_clientStorage, _entraUserService, _entraGroupService);
    }

    [Test]
    public async Task ValidateImportRoleMappingsAsync_WithInvalidMappingType_AddsError()
    {
        // Arrange
        var mappings = new List<RoleMappingValueObject>
        {
            new ApiResourceRoleMappingValueObject { MappingType = "InvalidType", Value = "val1", Description = "desc1" }
        };
        var status = new OperationStatus();

        // Act
        await _service.ValidateImportRoleMappingsAsync(mappings, status);

        // Assert
        Assert.That(status.Errors, Has.Some.Contain("Invalid Role Mapping Type"));
    }

    [Test]
    public async Task ValidateImportRoleMappingsAsync_WithBlankValue_AddsError()
    {
        // Arrange
        var mappings = new List<RoleMappingValueObject>
        {
            new ApiResourceRoleMappingValueObject { MappingType = nameof(RoleMapType.SecurityGroup), Value = "", Description = "desc1" }
        };
        var status = new OperationStatus();

        // Act
        await _service.ValidateImportRoleMappingsAsync(mappings, status);

        // Assert
        Assert.That(status.Errors, Has.Some.Contain("contains empty or blank values"));
    }

    [Test]
    public async Task ValidateImportRoleMappingsAsync_SecurityGroup_IfValid_SetsDescription()
    {
        // Arrange
        var mappings = new List<RoleMappingValueObject>
        {
            new ApiResourceRoleMappingValueObject { MappingType = nameof(RoleMapType.SecurityGroup), Value = "group1", Description = "desc1" }
        };
        _entraGroupService.GetGroupsByObjectIdsAsync(Arg.Any<IEnumerable<string>>())
            .Returns(new GroupResponse { Groups = new List<Group> { new() { Id = "group1", DisplayName = "Group One" } } });
        var status = new OperationStatus();

        // Act
        await _service.ValidateImportRoleMappingsAsync(mappings, status);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(status.Errors, Is.Empty);
            Assert.That(mappings[0].Description, Is.EqualTo("Group One"));
        }
    }

    [TestCase(null)]
    [TestCase("")]
    [TestCase("   ")]
    public async Task ValidateImportRoleMappingsAsync_SecurityGroup_IfStoredGroupNameEmpty_SetsDescription(string storedDisplayName)
    {
        // Arrange
        var mappings = new List<RoleMappingValueObject>
        {
            new ApiResourceRoleMappingValueObject() { MappingType = nameof(RoleMapType.SecurityGroup), Value = "group1", Description = "desc1" }
        };
        _entraGroupService.GetGroupsByObjectIdsAsync(Arg.Any<IEnumerable<string>>())
            .Returns(new GroupResponse { Groups = new List<Group> { new() { Id = "group1", DisplayName = storedDisplayName } } });
        var status = new OperationStatus();

        // Act
        await _service.ValidateImportRoleMappingsAsync(mappings, status);

        // Assert
        Assert.That(status.Errors, Has.Some.Contain("has no display name in Entra ID."));
    }

    [Test]
    public async Task ValidateImportRoleMappingsAsync_UserObjectId_IfValid_SetsDescription()
    {
        // Arrange
        var mappings = new List<RoleMappingValueObject>
        {
            new ApiResourceRoleMappingValueObject { MappingType = nameof(RoleMapType.UserObjectId), Value = "user1", Description = "desc1" }
        };
        _entraUserService.GetUsersByObjectIdsAsync(Arg.Any<IEnumerable<string>>())
            .Returns(new UserResponse { Users = new List<User> { new() { OId = "user1", DisplayName = "User One" } } });
        var status = new OperationStatus();

        // Act
        await _service.ValidateImportRoleMappingsAsync(mappings, status);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(status.Errors, Is.Empty);
            Assert.That(mappings[0].Description, Is.EqualTo("User One"));
        }
    }

    [TestCase(null)]
    [TestCase("")]
    [TestCase("   ")]
    public async Task ValidateImportRoleMappingsAsync_UserObjectId_IfStoredUserNameEmpty_AddsError(string storedDisplayName)
    {
        // Arrange
        var mappings = new List<RoleMappingValueObject>
        {
            new ApiResourceRoleMappingValueObject() { MappingType = nameof(RoleMapType.UserObjectId), Value = "user1", Description = "desc1" }
        };
        _entraUserService.GetUsersByObjectIdsAsync(Arg.Any<IEnumerable<string>>())
            .Returns(new UserResponse { Users = new List<User> { new() { OId = "user1", DisplayName = storedDisplayName } } });
        var status = new OperationStatus();

        // Act
        await _service.ValidateImportRoleMappingsAsync(mappings, status);

        // Assert
        Assert.That(status.Errors, Has.Some.Contain("has no display name in Entra ID."));
    }

    [Test]
    public async Task ValidateImportRoleMappingsAsync_ClientId_IfValid_SetsDescription()
    {
        // Arrange
        var mappings = new List<RoleMappingValueObject>
        {
            new ApiResourceRoleMappingValueObject { MappingType = nameof(RoleMapType.ClientId), Value = "client1", Description = "desc1" }
        };
        _clientStorage.ToListAsync(Arg.Any<System.Linq.Expressions.Expression<System.Func<ClientExt, bool>>>())
            .Returns(new List<ClientExt> { new() { ClientId = "client1", ClientName = "Client One", SystemPermissionEnvironment = Substitute.For<SystemPermissionEnvironment>() } });
        var status = new OperationStatus();

        // Act
        await _service.ValidateImportRoleMappingsAsync(mappings, status);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(status.Errors, Is.Empty);
            Assert.That(mappings[0].Description, Is.EqualTo("Client One"));
        }
    }

    [TestCase(null)]
    [TestCase("")]
    [TestCase("   ")]
    public async Task ValidateImportRoleMappingsAsync_ClientId_IfStoredNameEmpty_AddsError(string storedDisplayName)
    {
        // Arrange
        var mappings = new List<RoleMappingValueObject>
        {
            new ApiResourceRoleMappingValueObject() { MappingType = nameof(RoleMapType.ClientId), Value = "client1", Description = "desc1" }
        };
        _clientStorage.ToListAsync(Arg.Any<System.Linq.Expressions.Expression<System.Func<ClientExt, bool>>>())
            .Returns(new List<ClientExt> { new() { ClientId = "client1", ClientName = storedDisplayName, SystemPermissionEnvironment = Substitute.For<SystemPermissionEnvironment>() } });
        var status = new OperationStatus();

        // Act
        await _service.ValidateImportRoleMappingsAsync(mappings, status);

        // Assert
        Assert.That(status.Errors, Has.Some.Contain("has an empty name"));
    }

    [Test]
    public async Task ValidateImportRoleMappingsAsync_WithUnknownType_AddsError()
    {
        // Arrange
        var mappings = new List<RoleMappingValueObject>
        {
            new ApiResourceRoleMappingValueObject { MappingType = "999", Value = "something", Description = "desc" }
        };
        var status = new OperationStatus();

        // Act
        await _service.ValidateImportRoleMappingsAsync(mappings, status);

        // Assert
        Assert.That(status.Errors, Has.Some.Contain("Unknown mapping type"));
    }
}
