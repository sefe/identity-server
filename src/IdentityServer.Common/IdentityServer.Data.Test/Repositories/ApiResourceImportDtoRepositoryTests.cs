// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

using System.Security.Claims;
using NSubstitute;
using IdentityServer.Abstraction.Contracts;
using IdentityServer.Abstraction.DTO.Export;
using IdentityServer.Abstraction.DTO.Import;
using IdentityServer.Abstraction.Entities.IdentityServerConfig;
using IdentityServer.Abstraction.Entities.IdentityServerConfig.SystemPermissions;
using IdentityServer.Abstraction.Exceptions;
using IdentityServer.Abstraction.Extensions;
using IdentityServer.Data.DuendeEntityExtensions;
using IdentityServer.Data.Entities.Roles;
using IdentityServer.Data.Repositories.DtoRepositories.ApiResource;
using IdentityServer.Data.Services;
using IdentityServer.Tests.Common.Builders;

namespace IdentityServer.Data.Test.Repositories;

[TestFixture]
public class ApiResourceImportDtoRepositoryTests
{
    private const string _testResourceName = "test-resource";
    private const string _role1 = "role1";
    private const string _role2 = "role2";
    private const string _role3 = "role3";
    private const string _role4 = "role4";
    private const string _newRole = "newRole";
    private const string _existingRole = "existingRole";
    private const string _securityGroup = nameof(RoleMapType.SecurityGroup);
    private const string _clientId = nameof(RoleMapType.ClientId);
    private const string _userObjectId = nameof(RoleMapType.UserObjectId);
    private const string _val1 = "Val1";
    private const string _val2 = "Val2";
    private const string _desc1 = "desc1";
    private const string _desc2 = "desc2";
    private const string _modifiedDescription = "modified description";
    private const string _newMapping = "new mapping";
    private const string _originalDescription = "original description";
    private const string _error = "error";
    private const string _user1 = "user1";
    private const string _user2 = "user2";

    private IStorage<ApiResourceExt> _apiResourceStorage;
    private IStorage<ApiResourceRole> _roleStorage;
    private IPermissionChecker _permissionChecker;
    private IRoleMappingValidationService _roleMappingValidationService;
    private ApiResourceImportDtoRepository _sut;
    private ClaimsPrincipal _user;
    private ApiResourceExt _apiResource;
    private int _apiResourceId;

    [SetUp]
    public void SetUp()
    {
        _apiResourceStorage = Substitute.For<IStorage<ApiResourceExt>>();
        _roleStorage = Substitute.For<IStorage<ApiResourceRole>>();
        _permissionChecker = Substitute.For<IPermissionChecker>();
        _roleMappingValidationService = Substitute.For<IRoleMappingValidationService>();
        var logger = Substitute.For<Microsoft.Extensions.Logging.ILogger<ApiResourceImportDtoRepository>>();
        _sut = new ApiResourceImportDtoRepository(
            _apiResourceStorage,
            _roleStorage,
            _permissionChecker,
            logger,
            _roleMappingValidationService
        );
        _user = new ClaimsPrincipal();
        _apiResourceId = 42;
        _apiResource = new ApiResourceExtBuilder(_testResourceName).WithId(_apiResourceId).Build();
        _apiResource.Roles = new List<ApiResourceRole>();
    }

    [Test]
    public void ImportAsync_WhenApiResourceNotFound_ThrowsEntityNotFoundException()
    {
        // Arrange
        _apiResourceStorage.GetByIdAsync(_apiResourceId).Returns((ApiResourceExt)null);
        var dto = new ApiResourceRoleImportDto
        {
            ImportStrategy = ImportStrategy.Replace,
            Roles = new List<RoleValueObject<ApiResourceRoleMappingValueObject>>()
        };
        // Act & Assert
        Assert.That(
            async () => await _sut.ImportAsync(_user, _apiResourceId, dto),
            Throws.TypeOf<EntityNotFoundException>()
        );
    }

    [Test]
    public void ImportAsync_WhenValidationFails_ThrowsImportValidationException()
    {
        // Arrange
        _apiResourceStorage.GetByIdAsync(_apiResourceId).Returns(_apiResource);
        _permissionChecker.GetAccessRoleOrThrowIfNoAccessToEnvAsync(
            _user,
            _apiResource.SystemPermissionEnvironmentId,
            EntityAccessType.Update,
            _apiResource.ToString()
        ).Returns(SystemPermissionRoleType.Writer);
        var dto = new ApiResourceRoleImportDto
        {
            ImportStrategy = ImportStrategy.Replace,
            Roles = new List<RoleValueObject<ApiResourceRoleMappingValueObject>>()
        };
        _roleMappingValidationService.ValidateImportRoleMappingsAsync(
            Arg.Any<List<RoleMappingValueObject>>(),
            Arg.Any<OperationStatus>()
        ).Returns(ci =>
        {
            var status = ci.Arg<OperationStatus>();
            status.Errors.Add(_error);
            return Task.CompletedTask;
        });
        // Act & Assert
        Assert.That(
            async () => await _sut.ImportAsync(_user, _apiResourceId, dto),
            Throws.TypeOf<ImportValidationException>()
        );
    }

    [Test]
    public async Task ImportAsync_WithReplaceStrategy_ClearsAndAddsRolesAndMappings()
    {
        // Arrange
        _apiResourceStorage.GetByIdAsync(_apiResourceId).Returns(_apiResource);
        _permissionChecker.GetAccessRoleOrThrowIfNoAccessToEnvAsync(
            _user,
            _apiResource.SystemPermissionEnvironmentId,
            EntityAccessType.Update,
            _apiResource.ToString()
        ).Returns(SystemPermissionRoleType.Writer);
        var roleDto = new RoleValueObject<ApiResourceRoleMappingValueObject>
        {
            RoleName = _role1,
            Mappings = new List<ApiResourceRoleMappingValueObject>
            {
                new() {
                    MappingType = _securityGroup,
                    Value = _val1,
                    Description = _desc1
                }
            }
        };
        var dto = new ApiResourceRoleImportDto
        {
            ImportStrategy = ImportStrategy.Replace,
            Roles = new List<RoleValueObject<ApiResourceRoleMappingValueObject>> { roleDto }
        };
        // Act
        await _sut.ImportAsync(_user, _apiResourceId, dto);
        // Assert
        await _apiResourceStorage.Received(1).UpdateAsync(Arg.Any<ApiResourceExt>());
        Assert.That(_apiResource.Roles, Has.Count.EqualTo(1));
        Assert.That(_apiResource.Roles[0].RoleName, Is.EqualTo(_role1));
    }

    [Test]
    public async Task ImportAsync_WithAddStrategy_AddsNewRolesAndMappings()
    {
        // Arrange
        _apiResourceStorage.GetByIdAsync(_apiResourceId).Returns(_apiResource);
        _permissionChecker.GetAccessRoleOrThrowIfNoAccessToEnvAsync(
            _user,
            _apiResource.SystemPermissionEnvironmentId,
            EntityAccessType.Update,
            _apiResource.ToString()
        ).Returns(SystemPermissionRoleType.Writer);
        var roleDto = new RoleValueObject<ApiResourceRoleMappingValueObject>
        {
            RoleName = _role2,
            Mappings = new List<ApiResourceRoleMappingValueObject>
            {
                new() {
                    MappingType = _clientId,
                    Value = _val2,
                    Description = _desc2
                }
            }
        };
        var dto = new ApiResourceRoleImportDto
        {
            ImportStrategy = ImportStrategy.Add,
            Roles = new List<RoleValueObject<ApiResourceRoleMappingValueObject>> { roleDto }
        };
        // Act
        await _sut.ImportAsync(_user, _apiResourceId, dto);
        // Assert
        await _apiResourceStorage.Received(1).UpdateAsync(Arg.Any<ApiResourceExt>());
        Assert.That(_apiResource.Roles.Any(r => r.RoleName == _role2), Is.True);
    }

    [Test]
    public void ImportAsync_WithUnknownStrategy_ThrowsImportValidationException()
    {
        // Arrange
        _apiResourceStorage.GetByIdAsync(_apiResourceId).Returns(_apiResource);
        _permissionChecker.GetAccessRoleOrThrowIfNoAccessToEnvAsync(
            _user,
            _apiResource.SystemPermissionEnvironmentId,
            EntityAccessType.Update,
            _apiResource.ToString()
        ).Returns(SystemPermissionRoleType.Writer);
        var dto = new ApiResourceRoleImportDto
        {
            ImportStrategy = (ImportStrategy)999,
            Roles = new List<RoleValueObject<ApiResourceRoleMappingValueObject>>()
        };
        // Act & Assert
        Assert.That(
            async () => await _sut.ImportAsync(_user, _apiResourceId, dto),
            Throws.TypeOf<ImportValidationException>()
        );
    }

    [Test]
    public void ValidateImportAsync_WhenApiResourceNotFound_ThrowsEntityNotFoundException()
    {
        // Arrange
        _apiResourceStorage.GetByIdAsync(_apiResourceId).Returns((ApiResourceExt)null);
        var dto = new ApiResourceRoleImportDto
        {
            ImportStrategy = ImportStrategy.Replace,
            Roles = new List<RoleValueObject<ApiResourceRoleMappingValueObject>>()
        };
        // Act & Assert
        Assert.That(
            async () => await _sut.ValidateImportAsync(_user, _apiResourceId, dto),
            Throws.TypeOf<EntityNotFoundException>()
        );
    }

    [Test]
    public async Task ValidateImportAsync_WhenValid_ReturnsOperationStatus()
    {
        // Arrange
        _apiResourceStorage.GetByIdAsync(_apiResourceId).Returns(_apiResource);
        _permissionChecker.GetAccessRoleOrThrowIfNoAccessToEnvAsync(
            _user,
            _apiResource.SystemPermissionEnvironmentId,
            EntityAccessType.Read,
            _apiResource.ToString()
        ).Returns(SystemPermissionRoleType.Reader);
        var roleDto = new RoleValueObject<ApiResourceRoleMappingValueObject>
        {
            RoleName = _role3,
            Mappings = new List<ApiResourceRoleMappingValueObject>
            {
                new() {
                    MappingType = _userObjectId,
                    Value = _val1,
                    Description = _desc1
                }
            }
        };
        var dto = new ApiResourceRoleImportDto
        {
            ImportStrategy = ImportStrategy.Replace,
            Roles = new List<RoleValueObject<ApiResourceRoleMappingValueObject>> { roleDto }
        };
        // Act
        var result = await _sut.ValidateImportAsync(_user, _apiResourceId, dto);
        // Assert
        Assert.That(result, Is.Not.Null);
        Assert.That(result.HasErrors, Is.False);
    }

    [Test]
    public async Task ValidateImportImplAsync_WithValidInput_ReturnsOperationStatus()
    {
        // Arrange
        var roleDto = new RoleValueObject<ApiResourceRoleMappingValueObject>
        {
            RoleName = _role4,
            Mappings = new List<ApiResourceRoleMappingValueObject>
            {
                new() {
                    MappingType = _securityGroup,
                    Value = _val1,
                    Description = _desc1
                }
            }
        };
        var dto = new ApiResourceRoleImportDto
        {
            ImportStrategy = ImportStrategy.Replace,
            Roles = new List<RoleValueObject<ApiResourceRoleMappingValueObject>> { roleDto }
        };
        // Act
        var result = await _sut.ValidateImportImplAsync(_apiResourceId, dto);
        // Assert
        Assert.That(result, Is.Not.Null);
        Assert.That(result.HasErrors, Is.False);
    }

    [Test]
    public async Task ReplaceApiResourceRoles_WithValidInput_ReplacesRolesAndMappings()
    {
        // Arrange
        var currentApiResource = new ApiResourceExtBuilder(_testResourceName)
            .WithId(_apiResourceId)
            .WithRole(_existingRole, new List<Entities.Roles.RoleMapping>())
            .Build();

        _apiResourceStorage.UpdateAsync(Arg.Any<ApiResourceExt>()).Returns(currentApiResource);
        var roleDto = new RoleValueObject<ApiResourceRoleMappingValueObject>
        {
            RoleName = _newRole,
            Mappings = new List<ApiResourceRoleMappingValueObject>
            {
                new() {
                    MappingType = _securityGroup,
                    Value = _val1,
                    Description = _desc1
                }
            }
        };
        var dto = new ApiResourceRoleImportDto
        {
            ImportStrategy = ImportStrategy.Replace,
            Roles = new List<RoleValueObject<ApiResourceRoleMappingValueObject>> { roleDto }
        };
        // Act
        await _sut.ReplaceApiResourceRoles(dto, currentApiResource);
        // Assert
        Assert.That(currentApiResource.Roles, Has.Count.EqualTo(1));
        Assert.That(currentApiResource.Roles[0].RoleName, Is.EqualTo(_newRole));
    }

    [Test]
    public async Task MergeAddApiResourceRoles_WithValidInput_MergesRolesAndMappings()
    {
        // Arrange
        var currentApiResource = new ApiResourceExtBuilder(_testResourceName)
            .WithId(_apiResourceId)
            .WithRole(_existingRole, new List<Entities.Roles.RoleMapping>())
            .Build();

        _apiResourceStorage.UpdateAsync(Arg.Any<ApiResourceExt>()).Returns(currentApiResource);
        var roleDto = new RoleValueObject<ApiResourceRoleMappingValueObject>
        {
            RoleName = _newRole,
            Mappings = new List<ApiResourceRoleMappingValueObject>
            {
                new() {
                    MappingType = _securityGroup,
                    Value = _val1,
                    Description = _desc1
                }
            }
        };
        var dto = new ApiResourceRoleImportDto
        {
            ImportStrategy = ImportStrategy.Add,
            Roles = new List<RoleValueObject<ApiResourceRoleMappingValueObject>> { roleDto }
        };
        // Act
        await _sut.MergeAddApiResourceRoles(dto, currentApiResource);
        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(currentApiResource.Roles.Any(r => r.RoleName == _existingRole), Is.True);
            Assert.That(currentApiResource.Roles.Any(r => r.RoleName == _newRole), Is.True);
        }
    }

    [Test]
    public async Task MergeAddApiResourceRoles_WithDuplicateRoleMappings_DoesntOverrideExistingMapping()
    {
        // Arrange
        var existingMappings = new List<Entities.Roles.RoleMapping>
        {
            new() { MappingType = RoleMapType.UserObjectId, Value = _user1, Description = _originalDescription}
        };
        var currentApiResource = new ApiResourceExtBuilder(_testResourceName)
            .WithId(_apiResourceId)
            .WithRole(_existingRole, existingMappings)
            .Build();
        _apiResourceStorage.UpdateAsync(Arg.Any<ApiResourceExt>()).Returns(currentApiResource);
        var existingRoleDto = new RoleValueObject<ApiResourceRoleMappingValueObject>
        {
            RoleName = _existingRole,
            Mappings = new List<ApiResourceRoleMappingValueObject>
            {
                new() {
                    MappingType = _userObjectId,
                    Value = _user1,
                    Description = _modifiedDescription
                },
                new() {
                    MappingType = _userObjectId,
                    Value = _user2,
                    Description = _newMapping
                }
            }
        };
        var newRoleDto = new RoleValueObject<ApiResourceRoleMappingValueObject>
        {
            RoleName = _newRole,
            Mappings = new List<ApiResourceRoleMappingValueObject>
            {
                new() {
                    MappingType = _securityGroup,
                    Value = _val1,
                    Description = _desc1
                }
            }
        };
        var dto = new ApiResourceRoleImportDto
        {
            ImportStrategy = ImportStrategy.Add,
            Roles = new List<RoleValueObject<ApiResourceRoleMappingValueObject>> { newRoleDto, existingRoleDto }
        };
        // Act
        await _sut.MergeAddApiResourceRoles(dto, currentApiResource);
        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(currentApiResource.Roles.Any(r => r.RoleName == _newRole), Is.True);
            Assert.That(currentApiResource.Roles.Any(r => r.RoleName == _existingRole), Is.True);
            var existingRole = currentApiResource.Roles.First(r => r.RoleName == _existingRole);
            Assert.That(existingRole.Mappings, Has.Count.EqualTo(2));
            Assert.That(existingRole.Mappings.Count(rm => rm.MappingType == RoleMapType.UserObjectId && rm.Value.IsSame(_user1) && rm.Description.IsSame(_originalDescription)), Is.EqualTo(1));
        }
    }

    [Test]
    public async Task ReplaceApiResourceRoles_WithExistingRoles_UpdatesRolesBeforeDeletion()
    {
        // Arrange
        var existingRole = new ApiResourceRole
        {
            Id = 1,
            RoleName = _existingRole,
            ApiResourceId = _apiResourceId,
            Mappings = new List<RoleMapping>()
        };
        var currentApiResource = new ApiResourceExtBuilder(_testResourceName)
            .WithId(_apiResourceId)
            .Build();
        currentApiResource.Roles = new List<ApiResourceRole> { existingRole };

        _apiResourceStorage.UpdateAsync(Arg.Any<ApiResourceExt>()).Returns(currentApiResource);

        var roleDto = new RoleValueObject<ApiResourceRoleMappingValueObject>
        {
            RoleName = _newRole,
            Mappings = new List<ApiResourceRoleMappingValueObject>
            {
                new() {
                    MappingType = _securityGroup,
                    Value = _val1,
                    Description = _desc1
                }
            }
        };
        var dto = new ApiResourceRoleImportDto
        {
            ImportStrategy = ImportStrategy.Replace,
            Roles = new List<RoleValueObject<ApiResourceRoleMappingValueObject>> { roleDto }
        };

        // Act
        await _sut.ReplaceApiResourceRoles(dto, currentApiResource);

        // Assert
        await _roleStorage.Received(1).UpdateAsync(Arg.Is<ApiResourceRole>(r =>
            r.Id == existingRole.Id &&
            r.Updated != null));
    }

    [Test]
    public async Task ReplaceApiResourceRoles_WithExistingRolesAndMappings_UpdatesRoleMappingsBeforeDeletion()
    {
        // Arrange
        var existingMapping1 = new RoleMapping
        {
            Id = 1,
            Value = _val1,
            MappingType = RoleMapType.SecurityGroup,
            Description = _desc1
        };
        var existingMapping2 = new RoleMapping
        {
            Id = 2,
            Value = _val2,
            MappingType = RoleMapType.ClientId,
            Description = _desc2
        };
        var existingRole = new ApiResourceRole
        {
            Id = 1,
            RoleName = _existingRole,
            ApiResourceId = _apiResourceId,
            Mappings = new List<RoleMapping> { existingMapping1, existingMapping2 }
        };
        var currentApiResource = new ApiResourceExtBuilder(_testResourceName)
            .WithId(_apiResourceId)
            .Build();
        currentApiResource.Roles = new List<ApiResourceRole> { existingRole };

        _apiResourceStorage.UpdateAsync(Arg.Any<ApiResourceExt>()).Returns(currentApiResource);

        var roleDto = new RoleValueObject<ApiResourceRoleMappingValueObject>
        {
            RoleName = _newRole,
            Mappings = new List<ApiResourceRoleMappingValueObject>()
        };
        var dto = new ApiResourceRoleImportDto
        {
            ImportStrategy = ImportStrategy.Replace,
            Roles = new List<RoleValueObject<ApiResourceRoleMappingValueObject>> { roleDto }
        };

        // Act
        await _sut.ReplaceApiResourceRoles(dto, currentApiResource);

        // Assert
        await _roleStorage.Received(1).UpdateAsync(Arg.Is<ApiResourceRole>(r =>
            r.Id == existingRole.Id &&
            r.Updated != null &&
            r.Mappings.All(m => m.Updated != null)));
    }

    [Test]
    public async Task ReplaceApiResourceRoles_WithMultipleExistingRoles_UpdatesAllRolesBeforeDeletion()
    {
        // Arrange
        var existingRole1 = new ApiResourceRole
        {
            Id = 1,
            RoleName = _role1,
            ApiResourceId = _apiResourceId,
            Mappings = new List<RoleMapping>()
        };
        var existingRole2 = new ApiResourceRole
        {
            Id = 2,
            RoleName = _role2,
            ApiResourceId = _apiResourceId,
            Mappings = new List<RoleMapping>()
        };
        var existingRole3 = new ApiResourceRole
        {
            Id = 3,
            RoleName = _role3,
            ApiResourceId = _apiResourceId,
            Mappings = new List<RoleMapping>()
        };
        var currentApiResource = new ApiResourceExtBuilder(_testResourceName)
            .WithId(_apiResourceId)
            .Build();
        currentApiResource.Roles = new List<ApiResourceRole> { existingRole1, existingRole2, existingRole3 };

        _apiResourceStorage.UpdateAsync(Arg.Any<ApiResourceExt>()).Returns(currentApiResource);

        var dto = new ApiResourceRoleImportDto
        {
            ImportStrategy = ImportStrategy.Replace,
            Roles = new List<RoleValueObject<ApiResourceRoleMappingValueObject>>()
        };

        // Act
        await _sut.ReplaceApiResourceRoles(dto, currentApiResource);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            await _roleStorage.Received(3).UpdateAsync(Arg.Any<ApiResourceRole>());
            await _roleStorage.Received(1).UpdateAsync(Arg.Is<ApiResourceRole>(r => r.Id == existingRole1.Id && r.Updated != null));
            await _roleStorage.Received(1).UpdateAsync(Arg.Is<ApiResourceRole>(r => r.Id == existingRole2.Id && r.Updated != null));
            await _roleStorage.Received(1).UpdateAsync(Arg.Is<ApiResourceRole>(r => r.Id == existingRole3.Id && r.Updated != null));
        }
    }

    [Test]
    public async Task ReplaceApiResourceRoles_WithRoleWithMultipleMappings_UpdatesAllMappingsBeforeDeletion()
    {
        // Arrange
        var mapping1 = new RoleMapping
        {
            Id = 1,
            Value = _val1,
            MappingType = RoleMapType.SecurityGroup,
            Description = _desc1
        };
        var mapping2 = new RoleMapping
        {
            Id = 2,
            Value = _val2,
            MappingType = RoleMapType.ClientId,
            Description = _desc2
        };
        var mapping3 = new RoleMapping
        {
            Id = 3,
            Value = _user1,
            MappingType = RoleMapType.UserObjectId,
            Description = _originalDescription
        };
        var existingRole = new ApiResourceRole
        {
            Id = 1,
            RoleName = _existingRole,
            ApiResourceId = _apiResourceId,
            Mappings = new List<RoleMapping> { mapping1, mapping2, mapping3 }
        };
        var currentApiResource = new ApiResourceExtBuilder(_testResourceName)
            .WithId(_apiResourceId)
            .Build();
        currentApiResource.Roles = new List<ApiResourceRole> { existingRole };

        _apiResourceStorage.UpdateAsync(Arg.Any<ApiResourceExt>()).Returns(currentApiResource);

        var dto = new ApiResourceRoleImportDto
        {
            ImportStrategy = ImportStrategy.Replace,
            Roles = new List<RoleValueObject<ApiResourceRoleMappingValueObject>>()
        };

        // Act
        await _sut.ReplaceApiResourceRoles(dto, currentApiResource);

        // Assert
        await _roleStorage.Received(1).UpdateAsync(Arg.Is<ApiResourceRole>(r =>
            r.Id == existingRole.Id &&
            r.Mappings.Count == 3 &&
            r.Mappings.All(m => m.Updated != null)));
    }

    [Test]
    public async Task ReplaceApiResourceRoles_WithExistingRoles_SetsUpdatedTimestampToSameValueForAllRolesAndMappings()
    {
        // Arrange
        var mapping1 = new RoleMapping
        {
            Id = 1,
            Value = _val1,
            MappingType = RoleMapType.SecurityGroup
        };
        var mapping2 = new RoleMapping
        {
            Id = 2,
            Value = _val2,
            MappingType = RoleMapType.ClientId
        };
        var role1 = new ApiResourceRole
        {
            Id = 1,
            RoleName = _role1,
            ApiResourceId = _apiResourceId,
            Mappings = new List<RoleMapping> { mapping1 }
        };
        var role2 = new ApiResourceRole
        {
            Id = 2,
            RoleName = _role2,
            ApiResourceId = _apiResourceId,
            Mappings = new List<RoleMapping> { mapping2 }
        };
        var currentApiResource = new ApiResourceExtBuilder(_testResourceName)
            .WithId(_apiResourceId)
            .Build();
        currentApiResource.Roles = new List<ApiResourceRole> { role1, role2 };

        _apiResourceStorage.UpdateAsync(Arg.Any<ApiResourceExt>()).Returns(currentApiResource);

        var dto = new ApiResourceRoleImportDto
        {
            ImportStrategy = ImportStrategy.Replace,
            Roles = new List<RoleValueObject<ApiResourceRoleMappingValueObject>>()
        };

        DateTime? capturedTimestamp = null;

        await _roleStorage.UpdateAsync(Arg.Do<ApiResourceRole>(r =>
        {
            if (capturedTimestamp == null)
            {
                capturedTimestamp = r.Updated;
            }
        }));

        // Act
        await _sut.ReplaceApiResourceRoles(dto, currentApiResource);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            await _roleStorage.Received(2).UpdateAsync(Arg.Is<ApiResourceRole>(r =>
                r.Updated != null &&
                r.Updated == capturedTimestamp &&
                r.Mappings.All(m => m.Updated == capturedTimestamp)));
        }
    }

    [Test]
    public async Task ReplaceApiResourceRoles_WithNoExistingRoles_DoesNotCallRoleStorageUpdate()
    {
        // Arrange
        var currentApiResource = new ApiResourceExtBuilder(_testResourceName)
            .WithId(_apiResourceId)
            .Build();
        currentApiResource.Roles = new List<ApiResourceRole>();

        _apiResourceStorage.UpdateAsync(Arg.Any<ApiResourceExt>()).Returns(currentApiResource);

        var roleDto = new RoleValueObject<ApiResourceRoleMappingValueObject>
        {
            RoleName = _newRole,
            Mappings = new List<ApiResourceRoleMappingValueObject>
            {
                new() {
                    MappingType = _securityGroup,
                    Value = _val1,
                    Description = _desc1
                }
            }
        };
        var dto = new ApiResourceRoleImportDto
        {
            ImportStrategy = ImportStrategy.Replace,
            Roles = new List<RoleValueObject<ApiResourceRoleMappingValueObject>> { roleDto }
        };

        // Act
        await _sut.ReplaceApiResourceRoles(dto, currentApiResource);

        // Assert
        await _roleStorage.DidNotReceive().UpdateAsync(Arg.Any<ApiResourceRole>());
    }

    [Test]
    public async Task ReplaceApiResourceRoles_WithRoleWithoutMappings_UpdatesRoleWithEmptyMappingsList()
    {
        // Arrange
        var existingRole = new ApiResourceRole
        {
            Id = 1,
            RoleName = _existingRole,
            ApiResourceId = _apiResourceId,
            Mappings = new List<RoleMapping>()
        };
        var currentApiResource = new ApiResourceExtBuilder(_testResourceName)
            .WithId(_apiResourceId)
            .Build();
        currentApiResource.Roles = new List<ApiResourceRole> { existingRole };

        _apiResourceStorage.UpdateAsync(Arg.Any<ApiResourceExt>()).Returns(currentApiResource);

        var dto = new ApiResourceRoleImportDto
        {
            ImportStrategy = ImportStrategy.Replace,
            Roles = new List<RoleValueObject<ApiResourceRoleMappingValueObject>>()
        };

        // Act
        await _sut.ReplaceApiResourceRoles(dto, currentApiResource);

        // Assert
        await _roleStorage.Received(1).UpdateAsync(Arg.Is<ApiResourceRole>(r =>
            r.Id == existingRole.Id &&
            r.Updated != null &&
            r.Mappings.Count == 0));
    }
}
