using System.Security.Claims;
using Microsoft.Extensions.Logging;
using NSubstitute;
using IdentityServer.Abstraction.Contracts;
using IdentityServer.Abstraction.DTO.Export;
using IdentityServer.Abstraction.DTO.Import;
using IdentityServer.Abstraction.Entities.IdentityServerConfig;
using IdentityServer.Abstraction.Entities.IdentityServerConfig.SystemPermissions;
using IdentityServer.Abstraction.Exceptions;
using IdentityServer.Data.DuendeEntityExtensions;
using IdentityServer.Data.Entities.Roles;
using IdentityServer.Data.Repositories.DtoRepositories.Client;
using IdentityServer.Data.Services;
using IdentityServer.Tests.Common.Builders;

namespace IdentityServer.Data.Test.Repositories;

[TestFixture]
public class ClientImportDtoRepositoryTests
{
    private IStorage<ClientExt> _clientStorage;
    private IStorage<ClientRole> _roleStorage;
    private IPermissionChecker _permissionChecker;
    private IRoleMappingValidationService _roleMappingValidationService;
    private ClientImportDtoRepository _sut;
    private ClaimsPrincipal _user;
    private ClientExt _client;

    private const int _clientId = 99;
    private const string _clientIdentifier = "test-client";
    private const string _clientName = "test-client";
    private const string _role1 = "role1";
    private const string _role2 = "role2";
    private const string _role3 = "role3";
    private const string _role4 = "role4";
    private const string _newRole = "newRole";
    private const string _existingRole = "existingRole";
    private const string _originalDescription = "original description";
    private const string _mappingTypeSecurityGroup = nameof(ClientRoleMapType.SecurityGroup);
    private const string _mappingTypeUserObjectId = nameof(ClientRoleMapType.UserObjectId);
    private const string _value1 = "Val1";
    private const string _value2 = "Val2";
    private const string _desc1 = "desc1";
    private const string _desc2 = "desc2";
    private const string _user1 = "user1";
    private const string _user2 = "user2";

    [SetUp]
    public void SetUp()
    {
        _clientStorage = Substitute.For<IStorage<ClientExt>>();
        _roleStorage = Substitute.For<IStorage<ClientRole>>();
        _permissionChecker = Substitute.For<IPermissionChecker>();
        _roleMappingValidationService = Substitute.For<IRoleMappingValidationService>();
        var logger = Substitute.For<ILogger<ClientImportDtoRepository>>();
        _sut = new ClientImportDtoRepository(
            _clientStorage,
            _roleStorage,
            _permissionChecker,
            logger,
            _roleMappingValidationService
        );
        _user = new ClaimsPrincipal();
        _client = new ClientExtBuilder(_clientIdentifier, _clientName)
            .WithId(_clientId)
            .Build();
    }

    [Test]
    public void ImportAsync_WithUnknownImportStrategy_ThrowsImportValidationException()
    {
        // Arrange
        const string exceptionMessage = "Unknown import strategy for Client roles.";
        var resource = new ClientRoleImportDto
        {
            ImportStrategy = (ImportStrategy)999, // Unknown strategy
            Roles = new() { new RoleValueObject<ClientRoleMappingValueObject>
            {
                RoleName = _role1,
                Mappings = new List<ClientRoleMappingValueObject>
                {
                    new() {
                        MappingType = _mappingTypeSecurityGroup,
                        Value = _value1,
                        Description = _desc1
                    }
                }
            }},
            Metadata = new DtoMetadata()
        };

        _clientStorage.GetByIdAsync(_clientId).Returns(_client);
        _permissionChecker.GetAccessRoleOrThrowIfNoAccessToEnvAsync(_user, _client.SystemPermissionEnvironmentId, EntityAccessType.Update, _client.ToString()!).Returns(SystemPermissionRoleType.Writer);
        _roleMappingValidationService.ValidateImportRoleMappingsAsync(Arg.Any<List<RoleMappingValueObject>>(), Arg.Any<OperationStatus>()).Returns(Task.CompletedTask);

        // Act & Assert
        var ex = Assert.ThrowsAsync<ImportValidationException>(async () =>
            await _sut.ImportAsync(_user, _clientId, resource));

        using (Assert.EnterMultipleScope())
        {
            Assert.That(ex, Is.Not.Null);
            Assert.That(ex!.Message, Is.EqualTo(exceptionMessage));
            Assert.That(ex.ValidationSummary, Is.Not.Null);
        }
    }

    [Test]
    public void ImportAsync_WhenClientNotFound_ThrowsEntityNotFoundException()
    {
        // Arrange
        _clientStorage.GetByIdAsync(_clientId).Returns((ClientExt)null);
        var dto = new ClientRoleImportDto
        {
            ImportStrategy = ImportStrategy.Replace,
            Roles = new List<RoleValueObject<ClientRoleMappingValueObject>>()
        };
        // Act & Assert
        Assert.That(
            async () => await _sut.ImportAsync(_user, _clientId, dto),
            Throws.TypeOf<EntityNotFoundException>()
        );
    }

    [Test]
    public void ImportAsync_WhenValidationFails_ThrowsImportValidationException()
    {
        // Arrange
        _clientStorage.GetByIdAsync(_clientId).Returns(_client);
        _permissionChecker.GetAccessRoleOrThrowIfNoAccessToEnvAsync(
            _user,
            _client.SystemPermissionEnvironmentId,
            EntityAccessType.Update,
            _client.ToString()
        ).Returns(SystemPermissionRoleType.Writer);
        var dto = new ClientRoleImportDto
        {
            ImportStrategy = ImportStrategy.Replace,
            Roles = new List<RoleValueObject<ClientRoleMappingValueObject>>()
        };
        _roleMappingValidationService.ValidateImportRoleMappingsAsync(
            Arg.Any<List<RoleMappingValueObject>>(),
            Arg.Any<OperationStatus>()
        ).Returns(ci =>
        {
            var status = ci.Arg<OperationStatus>();
            status.Errors.Add("error");
            return Task.CompletedTask;
        });
        // Act & Assert
        Assert.That(
            async () => await _sut.ImportAsync(_user, _clientId, dto),
            Throws.TypeOf<ImportValidationException>()
        );
    }

    [Test]
    public async Task ImportAsync_WithReplaceStrategy_ClearsAndAddsRolesAndMappings()
    {
        // Arrange
        _clientStorage.GetByIdAsync(_clientId).Returns(_client);
        _permissionChecker.GetAccessRoleOrThrowIfNoAccessToEnvAsync(
            _user,
            _client.SystemPermissionEnvironmentId,
            EntityAccessType.Update,
            _client.ToString()
        ).Returns(SystemPermissionRoleType.Writer);
        var roleDto = new RoleValueObject<ClientRoleMappingValueObject>
        {
            RoleName = _role1,
            Mappings = new List<ClientRoleMappingValueObject>
            {
                new() {
                    MappingType = _mappingTypeSecurityGroup,
                    Value = _value1,
                    Description = _desc1
                }
            }
        };
        var dto = new ClientRoleImportDto
        {
            ImportStrategy = ImportStrategy.Replace,
            Roles = new List<RoleValueObject<ClientRoleMappingValueObject>> { roleDto }
        };
        // Act
        await _sut.ImportAsync(_user, _clientId, dto);
        // Assert
        await _clientStorage.Received(1).UpdateAsync(Arg.Any<ClientExt>());
        Assert.That(_client.Roles, Has.Count.EqualTo(1));
        Assert.That(_client.Roles[0].RoleName, Is.EqualTo(_role1));
    }

    [Test]
    public async Task ImportAsync_WithAddStrategy_AddsNewRolesAndMappings()
    {
        // Arrange
        _clientStorage.GetByIdAsync(_clientId).Returns(_client);
        _permissionChecker.GetAccessRoleOrThrowIfNoAccessToEnvAsync(
            _user,
            _client.SystemPermissionEnvironmentId,
            EntityAccessType.Update,
            _client.ToString()
        ).Returns(SystemPermissionRoleType.Writer);
        var roleDto = new RoleValueObject<ClientRoleMappingValueObject>
        {
            RoleName = _role2,
            Mappings = new List<ClientRoleMappingValueObject>
            {
                new() {
                    MappingType = _mappingTypeSecurityGroup,
                    Value = _value1,
                    Description = _desc1
                }
            }
        };
        var dto = new ClientRoleImportDto
        {
            ImportStrategy = ImportStrategy.Add,
            Roles = new List<RoleValueObject<ClientRoleMappingValueObject>> { roleDto }
        };
        // Act
        await _sut.ImportAsync(_user, _clientId, dto);
        // Assert
        await _clientStorage.Received(1).UpdateAsync(Arg.Any<ClientExt>());
        Assert.That(_client.Roles.Any(r => r.RoleName == "role2"), Is.True);
    }

    [Test]
    public void ImportAsync_WithUnknownStrategy_ThrowsImportValidationException()
    {
        // Arrange
        _clientStorage.GetByIdAsync(_clientId).Returns(_client);
        _permissionChecker.GetAccessRoleOrThrowIfNoAccessToEnvAsync(
            _user,
            _client.SystemPermissionEnvironmentId,
            EntityAccessType.Update,
            _client.ToString()
        ).Returns(SystemPermissionRoleType.Writer);
        var dto = new ClientRoleImportDto
        {
            ImportStrategy = (ImportStrategy)999,
            Roles = new List<RoleValueObject<ClientRoleMappingValueObject>>()
        };
        // Act & Assert
        Assert.That(
            async () => await _sut.ImportAsync(_user, _clientId, dto),
            Throws.TypeOf<ImportValidationException>()
        );
    }

    [Test]
    public void ValidateImportAsync_WhenClientNotFound_ThrowsEntityNotFoundException()
    {
        // Arrange
        _clientStorage.GetByIdAsync(_clientId).Returns((ClientExt)null);
        var dto = new ClientRoleImportDto
        {
            ImportStrategy = ImportStrategy.Replace,
            Roles = new List<RoleValueObject<ClientRoleMappingValueObject>>()
        };
        // Act & Assert
        Assert.That(
            async () => await _sut.ValidateImportAsync(_user, _clientId, dto),
            Throws.TypeOf<EntityNotFoundException>()
        );
    }

    [Test]
    public async Task ValidateImportAsync_WhenValid_ReturnsOperationStatus()
    {
        // Arrange
        _clientStorage.GetByIdAsync(_clientId).Returns(_client);
        _permissionChecker.GetAccessRoleOrThrowIfNoAccessToEnvAsync(
            _user,
            _client.SystemPermissionEnvironmentId,
            EntityAccessType.Read,
            _client.ToString()
        ).Returns(SystemPermissionRoleType.Reader);
        var roleDto = new RoleValueObject<ClientRoleMappingValueObject>
        {
            RoleName = _role3,
            Mappings = new List<ClientRoleMappingValueObject>
            {
                new() {
                    MappingType = _mappingTypeUserObjectId,
                    Value = _value1,
                    Description = _desc1
                }
            }
        };
        var dto = new ClientRoleImportDto
        {
            ImportStrategy = ImportStrategy.Replace,
            Roles = new List<RoleValueObject<ClientRoleMappingValueObject>> { roleDto }
        };
        // Act
        var result = await _sut.ValidateImportAsync(_user, _clientId, dto);
        // Assert
        Assert.That(result, Is.Not.Null);
        Assert.That(result.HasErrors, Is.False);
    }

    [Test]
    public async Task ValidateImportImplAsync_WithValidInput_ReturnsOperationStatus()
    {
        // Arrange
        var roleDto = new RoleValueObject<ClientRoleMappingValueObject>
        {
            RoleName = _role4,
            Mappings = new List<ClientRoleMappingValueObject>
            {
                new() {
                    MappingType = _mappingTypeSecurityGroup,
                    Value = _value1,
                    Description = _desc1
                }
            }
        };
        var dto = new ClientRoleImportDto
        {
            ImportStrategy = ImportStrategy.Replace,
            Roles = new List<RoleValueObject<ClientRoleMappingValueObject>> { roleDto }
        };
        // Act
        var result = await _sut.ValidateImportImplAsync(_clientId, dto);
        // Assert
        Assert.That(result, Is.Not.Null);
        Assert.That(result.HasErrors, Is.False);
    }

    [Test]
    public async Task ReplaceClientRoles_WithValidInput_ReplacesRolesAndMappings()
    {
        // Arrange
        var currentClient = new ClientExtBuilder(_clientIdentifier, _clientName)
            .WithId(_clientId)
            .WithRole("oldRole", new List<Entities.Roles.ClientRoleMapping>())
            .Build();
        _clientStorage.UpdateAsync(Arg.Any<ClientExt>()).Returns(currentClient);
        var roleDto = new RoleValueObject<ClientRoleMappingValueObject>
        {
            RoleName = _newRole,
            Mappings = new List<ClientRoleMappingValueObject>
            {
                new() {
                    MappingType = _mappingTypeSecurityGroup,
                    Value = _value1,
                    Description = _desc1
                }
            }
        };
        var dto = new ClientRoleImportDto
        {
            ImportStrategy = ImportStrategy.Replace,
            Roles = new List<RoleValueObject<ClientRoleMappingValueObject>> { roleDto }
        };
        // Act
        await _sut.ReplaceClientRoles(dto, currentClient);
        // Assert
        Assert.That(currentClient.Roles, Has.Count.EqualTo(1));
        Assert.That(currentClient.Roles[0].RoleName, Is.EqualTo("newRole"));
    }

    [Test]
    public async Task MergeAddClientRoles_WithValidInput_MergesRolesAndMappings()
    {
        // Arrange
        var currentClient = new ClientExtBuilder(_clientIdentifier, _clientName)
            .WithId(_clientId)
            .WithRole("existingRole", new List<Entities.Roles.ClientRoleMapping>())
            .Build();
        _clientStorage.UpdateAsync(Arg.Any<ClientExt>()).Returns(currentClient);
        var roleDto = new RoleValueObject<ClientRoleMappingValueObject>
        {
            RoleName = _newRole,
            Mappings = new List<ClientRoleMappingValueObject>
            {
                new() {
                    MappingType = _mappingTypeSecurityGroup,
                    Value = _value1,
                    Description = _desc1
                }
            }
        };
        var dto = new ClientRoleImportDto
        {
            ImportStrategy = ImportStrategy.Add,
            Roles = new List<RoleValueObject<ClientRoleMappingValueObject>> { roleDto }
        };
        // Act
        await _sut.MergeAddClientRoles(dto, currentClient);
        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(currentClient.Roles.Any(r => r.RoleName == "existingRole"), Is.True);
            Assert.That(currentClient.Roles.Any(r => r.RoleName == "newRole"), Is.True);
        }
    }

    [Test]
    public async Task ReplaceClientRoles_WithExistingRoles_UpdatesRolesBeforeDeletion()
    {
        // Arrange
        var existingRole = new ClientRole
        {
            Id = 1,
            RoleName = _existingRole,
            ClientId = _clientId,
            Mappings = new List<ClientRoleMapping>()
        };
        var currentClient = new ClientExtBuilder(_clientIdentifier, _clientName)
            .WithId(_clientId)
            .Build();
        currentClient.Roles = new List<ClientRole> { existingRole };

        _clientStorage.UpdateAsync(Arg.Any<ClientExt>()).Returns(currentClient);

        var roleDto = new RoleValueObject<ClientRoleMappingValueObject>
        {
            RoleName = _newRole,
            Mappings = new List<ClientRoleMappingValueObject>
            {
                new()
                {
                    MappingType = _mappingTypeSecurityGroup,
                    Value = _value1,
                    Description = _desc1
                }
            }
        };
        var dto = new ClientRoleImportDto
        {
            ImportStrategy = ImportStrategy.Replace,
            Roles = new List<RoleValueObject<ClientRoleMappingValueObject>> { roleDto }
        };

        // Act
        await _sut.ReplaceClientRoles(dto, currentClient);

        // Assert
        await _roleStorage.Received(1).UpdateAsync(Arg.Is<ClientRole>(r =>
            r.Id == existingRole.Id &&
            r.Updated != null));
    }

    [Test]
    public async Task ReplaceClientRoles_WithExistingRolesAndMappings_UpdatesRoleMappingsBeforeDeletion()
    {
        // Arrange
        var existingMapping1 = new ClientRoleMapping
        {
            Id = 1,
            Value = _value1,
            MappingType = ClientRoleMapType.SecurityGroup,
            Description = _desc1
        };
        var existingMapping2 = new ClientRoleMapping
        {
            Id = 2,
            Value = _value2,
            MappingType = ClientRoleMapType.UserObjectId,
            Description = _desc2
        };
        var existingRole = new ClientRole
        {
            Id = 1,
            RoleName = _existingRole,
            ClientId = _clientId,
            Mappings = new List<ClientRoleMapping> { existingMapping1, existingMapping2 }
        };
        var currentClient = new ClientExtBuilder(_clientIdentifier, _clientName)
            .WithId(_clientId)
            .Build();
        currentClient.Roles = new List<ClientRole> { existingRole };

        _clientStorage.UpdateAsync(Arg.Any<ClientExt>()).Returns(currentClient);

        var roleDto = new RoleValueObject<ClientRoleMappingValueObject>
        {
            RoleName = _newRole,
            Mappings = new List<ClientRoleMappingValueObject>()
        };
        var dto = new ClientRoleImportDto
        {
            ImportStrategy = ImportStrategy.Replace,
            Roles = new List<RoleValueObject<ClientRoleMappingValueObject>> { roleDto }
        };

        // Act
        await _sut.ReplaceClientRoles(dto, currentClient);

        // Assert
        await _roleStorage.Received(1).UpdateAsync(Arg.Is<ClientRole>(r =>
            r.Id == existingRole.Id &&
            r.Updated != null &&
            r.Mappings.All(m => m.Updated != null)));
    }

    [Test]
    public async Task ReplaceClientRoles_WithMultipleExistingRoles_UpdatesAllRolesBeforeDeletion()
    {
        // Arrange
        var existingRole1 = new ClientRole
        {
            Id = 1,
            RoleName = _role1,
            ClientId = _clientId,
            Mappings = new List<ClientRoleMapping>()
        };
        var existingRole2 = new ClientRole
        {
            Id = 2,
            RoleName = _role2,
            ClientId = _clientId,
            Mappings = new List<ClientRoleMapping>()
        };
        var existingRole3 = new ClientRole
        {
            Id = 3,
            RoleName = _role3,
            ClientId = _clientId,
            Mappings = new List<ClientRoleMapping>()
        };
        var currentClient = new ClientExtBuilder(_clientIdentifier, _clientName)
            .WithId(_clientId)
            .Build();
        currentClient.Roles = new List<ClientRole> { existingRole1, existingRole2, existingRole3 };

        _clientStorage.UpdateAsync(Arg.Any<ClientExt>()).Returns(currentClient);

        var dto = new ClientRoleImportDto
        {
            ImportStrategy = ImportStrategy.Replace,
            Roles = new List<RoleValueObject<ClientRoleMappingValueObject>>()
        };

        // Act
        await _sut.ReplaceClientRoles(dto, currentClient);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            await _roleStorage.Received(3).UpdateAsync(Arg.Any<ClientRole>());
            await _roleStorage.Received(1).UpdateAsync(Arg.Is<ClientRole>(r => r.Id == existingRole1.Id && r.Updated != null));
            await _roleStorage.Received(1).UpdateAsync(Arg.Is<ClientRole>(r => r.Id == existingRole2.Id && r.Updated != null));
            await _roleStorage.Received(1).UpdateAsync(Arg.Is<ClientRole>(r => r.Id == existingRole3.Id && r.Updated != null));
        }
    }

    [Test]
    public async Task ReplaceClientRoles_WithRoleWithMultipleMappings_UpdatesAllMappingsBeforeDeletion()
    {
        // Arrange
        var mapping1 = new ClientRoleMapping
        {
            Id = 1,
            Value = _value1,
            MappingType = ClientRoleMapType.SecurityGroup,
            Description = _desc1
        };
        var mapping2 = new ClientRoleMapping
        {
            Id = 2,
            Value = _value2,
            MappingType = ClientRoleMapType.UserObjectId,
            Description = _desc2
        };
        var mapping3 = new ClientRoleMapping
        {
            Id = 3,
            Value = _user1,
            MappingType = ClientRoleMapType.UserObjectId,
            Description = _originalDescription
        };
        var existingRole = new ClientRole
        {
            Id = 1,
            RoleName = _existingRole,
            ClientId = _clientId,
            Mappings = new List<ClientRoleMapping> { mapping1, mapping2, mapping3 }
        };
        var currentClient = new ClientExtBuilder(_clientIdentifier, _clientName)
            .WithId(_clientId)
            .Build();
        currentClient.Roles = new List<ClientRole> { existingRole };

        _clientStorage.UpdateAsync(Arg.Any<ClientExt>()).Returns(currentClient);

        var dto = new ClientRoleImportDto
        {
            ImportStrategy = ImportStrategy.Replace,
            Roles = new List<RoleValueObject<ClientRoleMappingValueObject>>()
        };

        // Act
        await _sut.ReplaceClientRoles(dto, currentClient);

        // Assert
        await _roleStorage.Received(1).UpdateAsync(Arg.Is<ClientRole>(r =>
            r.Id == existingRole.Id &&
            r.Mappings.Count == 3 &&
            r.Mappings.All(m => m.Updated != null)));
    }

    [Test]
    public async Task ReplaceClientRoles_WithExistingRoles_SetsUpdatedTimestampToSameValueForAllRolesAndMappings()
    {
        // Arrange
        var mapping1 = new ClientRoleMapping
        {
            Id = 1,
            Value = _value1,
            MappingType = ClientRoleMapType.SecurityGroup
        };
        var mapping2 = new ClientRoleMapping
        {
            Id = 2,
            Value = _value2,
            MappingType = ClientRoleMapType.UserObjectId
        };
        var role1 = new ClientRole
        {
            Id = 1,
            RoleName = _role1,
            ClientId = _clientId,
            Mappings = new List<ClientRoleMapping> { mapping1 }
        };
        var role2 = new ClientRole
        {
            Id = 2,
            RoleName = _role2,
            ClientId = _clientId,
            Mappings = new List<ClientRoleMapping> { mapping2 }
        };
        var currentClient = new ClientExtBuilder(_clientIdentifier, _clientName)
            .WithId(_clientId)
            .Build();
        currentClient.Roles = new List<ClientRole> { role1, role2 };

        _clientStorage.UpdateAsync(Arg.Any<ClientExt>()).Returns(currentClient);

        var dto = new ClientRoleImportDto
        {
            ImportStrategy = ImportStrategy.Replace,
            Roles = new List<RoleValueObject<ClientRoleMappingValueObject>>()
        };

        DateTime? capturedTimestamp = null;

        await _roleStorage.UpdateAsync(Arg.Do<ClientRole>(r =>
        {
            if (capturedTimestamp == null)
            {
                capturedTimestamp = r.Updated;
            }
        }));

        // Act
        await _sut.ReplaceClientRoles(dto, currentClient);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            await _roleStorage.Received(2).UpdateAsync(Arg.Is<ClientRole>(r =>
                r.Updated != null &&
                r.Updated == capturedTimestamp &&
                r.Mappings.All(m => m.Updated == capturedTimestamp)));
        }
    }

    [Test]
    public async Task ReplaceClientRoles_WithNoExistingRoles_DoesNotCallRoleStorageUpdate()
    {
        // Arrange
        var currentClient = new ClientExtBuilder(_clientIdentifier, _clientName)
            .WithId(_clientId)
            .Build();
        currentClient.Roles = new List<ClientRole>();

        _clientStorage.UpdateAsync(Arg.Any<ClientExt>()).Returns(currentClient);

        var roleDto = new RoleValueObject<ClientRoleMappingValueObject>
        {
            RoleName = _newRole,
            Mappings = new List<ClientRoleMappingValueObject>
            {
                new()
                {
                    MappingType = _mappingTypeSecurityGroup,
                    Value = _value1,
                    Description = _desc1
                }
            }
        };
        var dto = new ClientRoleImportDto
        {
            ImportStrategy = ImportStrategy.Replace,
            Roles = new List<RoleValueObject<ClientRoleMappingValueObject>> { roleDto }
        };

        // Act
        await _sut.ReplaceClientRoles(dto, currentClient);

        // Assert
        await _roleStorage.DidNotReceive().UpdateAsync(Arg.Any<ClientRole>());
    }

    [Test]
    public async Task ReplaceClientRoles_WithRoleWithoutMappings_UpdatesRoleWithEmptyMappingsList()
    {
        // Arrange
        var existingRole = new ClientRole
        {
            Id = 1,
            RoleName = _existingRole,
            ClientId = _clientId,
            Mappings = new List<ClientRoleMapping>()
        };
        var currentClient = new ClientExtBuilder(_clientIdentifier, _clientName)
            .WithId(_clientId)
            .Build();
        currentClient.Roles = new List<ClientRole> { existingRole };

        _clientStorage.UpdateAsync(Arg.Any<ClientExt>()).Returns(currentClient);

        var dto = new ClientRoleImportDto
        {
            ImportStrategy = ImportStrategy.Replace,
            Roles = new List<RoleValueObject<ClientRoleMappingValueObject>>()
        };

        // Act
        await _sut.ReplaceClientRoles(dto, currentClient);

        // Assert
        await _roleStorage.Received(1).UpdateAsync(Arg.Is<ClientRole>(r =>
            r.Id == existingRole.Id &&
            r.Updated != null &&
            r.Mappings.Count == 0));
    }
}
