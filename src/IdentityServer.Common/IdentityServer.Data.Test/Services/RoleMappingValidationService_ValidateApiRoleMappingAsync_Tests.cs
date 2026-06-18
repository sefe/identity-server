using NSubstitute;
using IdentityServer.Abstraction.Contracts;
using IdentityServer.Abstraction.Contracts.MicrosoftGraph;
using IdentityServer.Abstraction.Entities.EntraEntities;
using IdentityServer.Abstraction.Entities.IdentityServerConfig;
using IdentityServer.Abstraction.Entities.IdentityServerConfig.SystemPermissions;
using IdentityServer.Data.DuendeEntityExtensions;
using IdentityServer.Data.Entities.Roles;
using IdentityServer.Data.Services;

namespace IdentityServer.Data.Test.Services;

[TestFixture]
public class RoleMappingValidationService_ValidateApiRoleMappingAsync_Tests
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
    public async Task ValidateApiRoleMappingAsync_WithNullOrWhitespaceValue_ReturnsError()
    {
        // Arrange
        var mapping = new RoleMapping { MappingType = RoleMapType.SecurityGroup, Value = " ", Description = null };

        // Act
        var result = await _service.ValidateApiRoleMappingAsync(mapping);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result.Errors, Has.Count.EqualTo(1));
            Assert.That(result.Errors[0], Does.Contain("cannot be empty"));
        }
    }

    [Test]
    public async Task ValidateApiRoleMappingAsync_SecurityGroup_IfGroupNotFound_ReturnsError()
    {
        // Arrange
        var mapping = new RoleMapping { MappingType = RoleMapType.SecurityGroup, Value = "group1", Description = "desc" };
        _entraGroupService.GetGroupByObjectIdAsync("group1").Returns(new GroupResponse { Groups = new List<Group>() });

        // Act
        var result = await _service.ValidateApiRoleMappingAsync(mapping);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result.Errors, Has.Count.GreaterThanOrEqualTo(1));
            Assert.That(result.Errors[0], Does.Contain("does not exist"));
        }
    }

    [Test]
    public async Task ValidateApiRoleMappingAsync_SecurityGroup_IfGroupFound_SetsDescription()
    {
        // Arrange
        var mapping = new RoleMapping { MappingType = RoleMapType.SecurityGroup, Value = "group1", Description = "desc" };
        _entraGroupService.GetGroupByObjectIdAsync("group1").Returns(new GroupResponse { Groups = new List<Group> { new() { Id = "group1", DisplayName = "Group One" } } });

        // Act
        var result = await _service.ValidateApiRoleMappingAsync(mapping);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result.Errors, Is.Empty);
            Assert.That(mapping.Description, Is.EqualTo("Group One"));
        }
    }

    [TestCase(null)]
    [TestCase("")]
    [TestCase("   ")]
    public async Task ValidateApiRoleMappingAsync_SecurityGroup_IfStoredGroupNameEmpty_ReturnsError(string storedDisplayName)
    {
        // Arrange
        var mapping = new RoleMapping { MappingType = RoleMapType.SecurityGroup, Value = "group1", Description = "desc" };
        _entraGroupService.GetGroupByObjectIdAsync("group1").Returns(new GroupResponse { Groups = new List<Group> { new() { Id = "group1", DisplayName = storedDisplayName } } });

        // Act
        var result = await _service.ValidateApiRoleMappingAsync(mapping);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result.Errors, Has.Count.GreaterThanOrEqualTo(1));
            Assert.That(result.Errors[0], Does.Contain("has no display name in Entra ID"));
        }
    }

    [Test]
    public async Task ValidateApiRoleMappingAsync_UserObjectId_IfUserNotFound_ReturnsError()
    {
        // Arrange
        var mapping = new RoleMapping { MappingType = RoleMapType.UserObjectId, Value = "user1", Description = "desc" };
        _entraUserService.GetUserByObjectIdAsync("user1").Returns(new UserResponse { Users = new List<User>() });

        // Act
        var result = await _service.ValidateApiRoleMappingAsync(mapping);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result.Errors, Has.Count.GreaterThanOrEqualTo(1));
            Assert.That(result.Errors[0], Does.Contain("does not exist"));
        }
    }

    [Test]
    public async Task ValidateApiRoleMappingAsync_UserObjectId_IfUserFound_SetsDescription()
    {
        // Arrange
        var mapping = new RoleMapping { MappingType = RoleMapType.UserObjectId, Value = "user1", Description = "desc" };
        _entraUserService.GetUserByObjectIdAsync("user1").Returns(new UserResponse { Users = new List<User> { new() { OId = "user1", DisplayName = "User One" } } });

        // Act
        var result = await _service.ValidateApiRoleMappingAsync(mapping);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result.Errors, Is.Empty);
            Assert.That(mapping.Description, Is.EqualTo("User One"));
        }
    }

    [TestCase(null)]
    [TestCase("")]
    [TestCase("   ")]
    public async Task ValidateApiRoleMappingAsync_UserObjectId_IfStoredUserNameEmpty_ReturnsError(string storedDisplayName)
    {
        // Arrange
        var mapping = new RoleMapping { MappingType = RoleMapType.UserObjectId, Value = "user1", Description = "desc" };
        _entraUserService.GetUserByObjectIdAsync("user1").Returns(new UserResponse { Users = new List<User> { new() { OId = "user1", DisplayName = storedDisplayName } } });

        // Act
        var result = await _service.ValidateApiRoleMappingAsync(mapping);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result.Errors, Has.Count.GreaterThanOrEqualTo(1));
            Assert.That(result.Errors[0], Does.Contain("has no display name in Entra ID"));
        }
    }

    [Test]
    public async Task ValidateApiRoleMappingAsync_ClientId_IfClientNotFound_ReturnsError()
    {
        // Arrange
        var mapping = new RoleMapping { MappingType = RoleMapType.ClientId, Value = "client1", Description = "desc" };
        _clientStorage.ToListAsync(Arg.Any<System.Linq.Expressions.Expression<System.Func<ClientExt, bool>>>()).Returns(new List<ClientExt>());

        // Act
        var result = await _service.ValidateApiRoleMappingAsync(mapping);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result.Errors, Has.Count.GreaterThanOrEqualTo(1));
            Assert.That(result.Errors[0], Does.Contain("does not exist"));
        }
    }

    [Test]
    public async Task ValidateApiRoleMappingAsync_ClientId_IfClientFound_SetsDescription()
    {
        // Arrange
        var mapping = new RoleMapping { MappingType = RoleMapType.ClientId, Value = "client1", Description = "desc" };
        _clientStorage.ToListAsync(Arg.Any<System.Linq.Expressions.Expression<System.Func<ClientExt, bool>>>()).Returns(new List<ClientExt> { new() { ClientId = "client1", ClientName = "Client One", SystemPermissionEnvironment = Substitute.For<SystemPermissionEnvironment>() } });

        // Act
        var result = await _service.ValidateApiRoleMappingAsync(mapping);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result.Errors, Is.Empty);
            Assert.That(mapping.Description, Is.EqualTo("Client One"));
        }
    }

    [TestCase(null)]
    [TestCase("")]
    [TestCase("   ")]
    public async Task ValidateApiRoleMappingAsync_ClientId_IfStoredClientNameEmpty_ReturnsError(string storedDisplayName)
    {
        // Arrange
        var mapping = new RoleMapping { MappingType = RoleMapType.ClientId, Value = "client1", Description = "desc" };
        _clientStorage.ToListAsync(Arg.Any<System.Linq.Expressions.Expression<System.Func<ClientExt, bool>>>()).Returns(new List<ClientExt> { new() { ClientId = "client1", ClientName = storedDisplayName, SystemPermissionEnvironment = Substitute.For<SystemPermissionEnvironment>() } });

        // Act
        var result = await _service.ValidateApiRoleMappingAsync(mapping);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result.Errors, Has.Count.GreaterThanOrEqualTo(1));
            Assert.That(result.Errors[0], Does.Contain("has an empty name."));
        }
    }

    [Test]
    public async Task ValidateApiRoleMappingAsync_IfUnknownType_ReturnsError()
    {
        // Arrange
        var mapping = new RoleMapping { MappingType = (RoleMapType)999, Value = "something", Description = "desc" };

        // Act
        var result = await _service.ValidateApiRoleMappingAsync(mapping);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result.Errors, Has.Count.EqualTo(1));
            Assert.That(result.Errors[0], Does.Contain("Unknown mapping type"));
        }
    }
}
