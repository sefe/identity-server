using IdentityServer.Abstraction.DTO.ApiResources;
using IdentityServer.Abstraction.DTO.Clients;
using IdentityServer.Abstraction.DTO.Export;
using IdentityServer.Abstraction.DTO.Import;
using IdentityServer.Abstraction.Entities.IdentityServerConfig;
using IdentityServer.AdminPortal.Web.Models.RoleImport;
using IdentityServer.AdminPortal.Web.Services.RoleImport;

namespace IdentityServer.AdminPortal.Test.Services.RoleImport;

[TestFixture]
public class RoleImportComparerTests
{
    private const string _role1Name = "Role1";
    private const string _role2Name = "Role2";

    private static class RoleMapTypeStrings
    {
        public const string UserObjectId = "UserObjectId";
        public const string ClientId = "ClientId";
        public const string SecurityGroup = "SecurityGroup";
    }

    [Test]
    public async Task CompareWithAsync_WithReplaceStrategy_DelegatesToRoleReplaceComparer()
    {
        // Arrange
        var existingRoles = new List<ApiResourcePropertyRoleDtoRead>
        {
            MakeApiResourceRole(_role1Name, MakeApiResourceMapping(RoleMapTypeStrings.UserObjectId, "1", "Admin User"))
        };
        var comparer = new RoleImportComparer<ApiResourceRoleMappingValueObject>(existingRoles, ConvertToApiResourceRoleMapping);
        var importDto = CreateApiResourceImportDto(ImportStrategy.Replace,
            MakeApiResourceRoleValue(_role2Name, MakeApiResourceMappingValue(RoleMapTypeStrings.UserObjectId, "2", "Regular User")));

        // Act
        var result = await comparer.CompareWithAsync(importDto, ImportStrategy.Replace);

        // Assert
        Assert.That(result, Is.Not.Empty);
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result, Has.Count.EqualTo(2)); // One removed, one added
            Assert.That(result.Any(r => r.RoleName == _role1Name && r.RoleState == ComparisonState.Removed), Is.True);
            Assert.That(result.Any(r => r.RoleName == _role2Name && r.RoleState == ComparisonState.Added), Is.True);
        }
    }

    [Test]
    public async Task CompareWithAsync_WithAddStrategy_DelegatesToRoleAddComparer()
    {
        // Arrange
        var existingRoles = new List<ApiResourcePropertyRoleDtoRead>
        {
            MakeApiResourceRole(_role1Name, MakeApiResourceMapping(RoleMapTypeStrings.UserObjectId, "1", "Admin User"))
        };
        var comparer = new RoleImportComparer<ApiResourceRoleMappingValueObject>(existingRoles, ConvertToApiResourceRoleMapping);
        var importDto = CreateApiResourceImportDto(ImportStrategy.Add,
            MakeApiResourceRoleValue(_role2Name, MakeApiResourceMappingValue(RoleMapTypeStrings.UserObjectId, "2", "Regular User")));

        // Act
        var result = await comparer.CompareWithAsync(importDto, ImportStrategy.Add);

        // Assert
        Assert.That(result, Is.Not.Empty);
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result, Has.Count.EqualTo(2)); // One unchanged, one added
            Assert.That(result.Any(r => r.RoleName == _role1Name && r.RoleState == ComparisonState.Unchanged), Is.True);
            Assert.That(result.Any(r => r.RoleName == _role2Name && r.RoleState == ComparisonState.Added), Is.True);
        }
    }

    [Test]
    public void CompareWithAsync_WithUnsupportedStrategy_ThrowsInvalidOperationException()
    {
        // Arrange
        var existingRoles = new List<ApiResourcePropertyRoleDtoRead>();
        var comparer = new RoleImportComparer<ApiResourceRoleMappingValueObject>(existingRoles, ConvertToApiResourceRoleMapping);
        var importDto = CreateApiResourceImportDto(ImportStrategy.Replace);

        // Act & Assert
        var ex = Assert.ThrowsAsync<InvalidOperationException>(() =>
            comparer.CompareWithAsync(importDto, (ImportStrategy)999));

        using (Assert.EnterMultipleScope())
        {
            Assert.That(ex, Is.Not.Null);
            Assert.That(ex.Message, Does.Contain("Import strategy '999' is not supported"));
        }
    }

    [Test]
    public async Task CompareWithAsync_ApiResourceConstructor_WorksCorrectly()
    {
        // Arrange
        var existingRoles = new List<ApiResourcePropertyRoleDtoRead>
        {
            MakeApiResourceRole(_role1Name,
                MakeApiResourceMapping(RoleMapTypeStrings.UserObjectId, "user1", "Test User"),
                MakeApiResourceMapping(RoleMapTypeStrings.SecurityGroup, "group1", "Test Group"))
        };
        var comparer = new RoleImportComparer<ApiResourceRoleMappingValueObject>(existingRoles, ConvertToApiResourceRoleMapping);
        var importDto = CreateApiResourceImportDto(ImportStrategy.Add,
            MakeApiResourceRoleValue(_role1Name,
                MakeApiResourceMappingValue(RoleMapTypeStrings.UserObjectId, "user1", "Updated User"),
                MakeApiResourceMappingValue(RoleMapTypeStrings.ClientId, "client1", "Test Client")));

        // Act
        var result = await comparer.CompareWithAsync(importDto, ImportStrategy.Add);

        // Assert
        Assert.That(result, Has.Count.EqualTo(1));
        var role = result[0];
        using (Assert.EnterMultipleScope())
        {
            Assert.That(role.RoleName, Is.EqualTo(_role1Name));
            Assert.That(role.RoleState, Is.EqualTo(ComparisonState.Unchanged));
            Assert.That(role.RoleMappingState, Is.EqualTo(ComparisonState.Mixed));
            Assert.That(role.Mappings, Has.Count.EqualTo(3)); // 1 unchanged, 1 unchanged, 1 added
        }
        var mappings = role.Mappings;
        using (Assert.EnterMultipleScope())
        {
            Assert.That(mappings.Any(m => m.State == ComparisonState.Unchanged && m.Existing.MappingType == RoleMapTypeStrings.SecurityGroup), Is.True);
            Assert.That(mappings.Any(m => m.State == ComparisonState.Conflict && m.Existing.MappingType == RoleMapTypeStrings.UserObjectId), Is.True);
            Assert.That(mappings.Any(m => m.State == ComparisonState.Added && m.Imported.MappingType == RoleMapTypeStrings.ClientId), Is.True);
        }
    }

    [Test]
    public async Task CompareWithAsync_ClientConstructor_WorksCorrectly()
    {
        // Arrange
        var existingRoles = new List<ClientPropertyRoleDtoRead>
        {
            MakeClientRole(_role1Name,
                MakeClientMapping(RoleMapTypeStrings.UserObjectId, "user1", "Test User"),
                MakeClientMapping(RoleMapTypeStrings.SecurityGroup, "group1", "Test Group"))
        };
        var comparer = new RoleImportComparer<ClientRoleMappingValueObject>(existingRoles, ConvertToClientRoleMapping);
        var importDto = CreateClientImportDto(ImportStrategy.Replace,
            MakeClientRoleValue(_role1Name,
                MakeClientMappingValue(RoleMapTypeStrings.UserObjectId, "user1", "Updated User"),
                MakeClientMappingValue(RoleMapTypeStrings.ClientId, "client1", "Test Client")));

        // Act
        var result = await comparer.CompareWithAsync(importDto, ImportStrategy.Replace);

        // Assert
        Assert.That(result, Has.Count.EqualTo(1));
        var role = result[0];
        using (Assert.EnterMultipleScope())
        {
            Assert.That(role.RoleName, Is.EqualTo(_role1Name));
            Assert.That(role.RoleState, Is.EqualTo(ComparisonState.Unchanged));
            Assert.That(role.RoleMappingState, Is.EqualTo(ComparisonState.Mixed));
            Assert.That(role.Mappings, Has.Count.EqualTo(3)); // 1 removed, 1 changed, 1 added
        }
        var mappings = role.Mappings;
        using (Assert.EnterMultipleScope())
        {
            Assert.That(mappings.Any(m => m.State == ComparisonState.Removed && m.Existing.MappingType == RoleMapTypeStrings.SecurityGroup), Is.True);
            Assert.That(mappings.Any(m => m.State == ComparisonState.Changed && m.Existing.MappingType == RoleMapTypeStrings.UserObjectId), Is.True);
            Assert.That(mappings.Any(m => m.State == ComparisonState.Added && m.Imported.MappingType == RoleMapTypeStrings.ClientId), Is.True);
        }
    }

    [Test]
    public async Task CompareWithAsync_EmptyExistingRoles_ReturnsAllImportedAsAdded()
    {
        // Arrange
        var existingRoles = new List<ApiResourcePropertyRoleDtoRead>();
        var comparer = new RoleImportComparer<ApiResourceRoleMappingValueObject>(existingRoles, ConvertToApiResourceRoleMapping);
        var importDto = CreateApiResourceImportDto(ImportStrategy.Add,
            MakeApiResourceRoleValue(_role1Name, MakeApiResourceMappingValue(RoleMapTypeStrings.UserObjectId, "user1")),
            MakeApiResourceRoleValue(_role2Name, MakeApiResourceMappingValue(RoleMapTypeStrings.ClientId, "client1")));

        // Act
        var result = await comparer.CompareWithAsync(importDto, ImportStrategy.Add);

        // Assert
        Assert.That(result, Has.Count.EqualTo(2));
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result.All(r => r.RoleState == ComparisonState.Added), Is.True);
            Assert.That(result.Any(r => r.RoleName == _role1Name), Is.True);
            Assert.That(result.Any(r => r.RoleName == _role2Name), Is.True);
        }
    }

    [Test]
    public async Task CompareWithAsync_EmptyImportedRoles_WithReplaceStrategy_ReturnsAllExistingAsRemoved()
    {
        // Arrange
        var existingRoles = new List<ClientPropertyRoleDtoRead>
        {
            MakeClientRole(_role1Name, MakeClientMapping(RoleMapTypeStrings.UserObjectId, "user1")),
            MakeClientRole(_role2Name, MakeClientMapping(RoleMapTypeStrings.SecurityGroup, "group1"))
        };
        var comparer = new RoleImportComparer<ClientRoleMappingValueObject>(existingRoles, ConvertToClientRoleMapping);
        var importDto = CreateClientImportDto(ImportStrategy.Replace);

        // Act
        var result = await comparer.CompareWithAsync(importDto, ImportStrategy.Replace);

        // Assert
        Assert.That(result, Has.Count.EqualTo(2));
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result.All(r => r.RoleState == ComparisonState.Removed), Is.True);
            Assert.That(result.Any(r => r.RoleName == _role1Name), Is.True);
            Assert.That(result.Any(r => r.RoleName == _role2Name), Is.True);
        }
    }

    [Test]
    public async Task CompareWithAsync_EmptyImportedRoles_WithAddStrategy_ReturnsAllExistingAsUnchanged()
    {
        // Arrange
        var existingRoles = new List<ApiResourcePropertyRoleDtoRead>
        {
            MakeApiResourceRole(_role1Name, MakeApiResourceMapping(RoleMapTypeStrings.UserObjectId, "user1")),
            MakeApiResourceRole(_role2Name, MakeApiResourceMapping(RoleMapTypeStrings.SecurityGroup, "group1"))
        };
        var comparer = new RoleImportComparer<ApiResourceRoleMappingValueObject>(existingRoles, ConvertToApiResourceRoleMapping);
        var importDto = CreateApiResourceImportDto(ImportStrategy.Add);

        // Act
        var result = await comparer.CompareWithAsync(importDto, ImportStrategy.Add);

        // Assert
        Assert.That(result, Has.Count.EqualTo(2));
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result.All(r => r.RoleState == ComparisonState.Unchanged), Is.True);
            Assert.That(result.Any(r => r.RoleName == _role1Name), Is.True);
            Assert.That(result.Any(r => r.RoleName == _role2Name), Is.True);
        }
    }

    // Helper methods to create test data
    private static ApiResourcePropertyRoleDtoRead MakeApiResourceRole(string name, params ApiResourcePropertyRoleMappingDtoRead[] mappings) =>
        new()
        {
            Id = 1,
            ApiResourceId = 1,
            RoleName = name,
            Mappings = mappings.ToList()
        };

    private static ClientPropertyRoleDtoRead MakeClientRole(string name, params ClientPropertyRoleMappingDtoRead[] mappings) =>
        new()
        {
            Id = 1,
            ClientId = 1,
            RoleName = name,
            Mappings = mappings.ToList()
        };

    private static ApiResourcePropertyRoleMappingDtoRead MakeApiResourceMapping(string type, string value, string desc = null) =>
        new()
        {
            Id = 1,
            ApiResourceRoleId = 1,
            MappingType = Enum.Parse<RoleMapType>(type),
            Value = value,
            Description = desc
        };

    private static ClientPropertyRoleMappingDtoRead MakeClientMapping(string type, string value, string desc = null) =>
        new()
        {
            Id = 1,
            ClientRoleId = 1,
            MappingType = Enum.Parse<ClientRoleMapType>(type),
            Value = value,
            Description = desc
        };

    private static ApiResourceRoleMappingValueObject ConvertToApiResourceRoleMapping(ApiResourcePropertyRoleMappingDtoRead dto) =>
        new()
        {
            MappingType = dto.MappingType.ToString(),
            Value = dto.Value,
            Description = dto.Description
        };

    private static ClientRoleMappingValueObject ConvertToClientRoleMapping(ClientPropertyRoleMappingDtoRead dto) =>
        new()
        {
            MappingType = dto.MappingType.ToString(),
            Value = dto.Value,
            Description = dto.Description
        };

    private static ApiResourceRoleImportDto CreateApiResourceImportDto(ImportStrategy strategy, params RoleValueObject<ApiResourceRoleMappingValueObject>[] roles) =>
        new()
        {
            ImportStrategy = strategy,
            Roles = roles.ToList()
        };

    private static ClientRoleImportDto CreateClientImportDto(ImportStrategy strategy, params RoleValueObject<ClientRoleMappingValueObject>[] roles) =>
        new()
        {
            ImportStrategy = strategy,
            Roles = roles.ToList()
        };

    private static RoleValueObject<ApiResourceRoleMappingValueObject> MakeApiResourceRoleValue(string name, params ApiResourceRoleMappingValueObject[] mappings) =>
        new()
        {
            RoleName = name,
            Mappings = mappings.ToList()
        };

    private static ApiResourceRoleMappingValueObject MakeApiResourceMappingValue(string type, string value, string desc = null) =>
        new()
        {
            MappingType = type,
            Value = value,
            Description = desc
        };

    private static ClientRoleMappingValueObject MakeClientMappingValue(string type, string value, string desc = null) =>
        new()
        {
            MappingType = type,
            Value = value,
            Description = desc
        };

    private static RoleValueObject<ClientRoleMappingValueObject> MakeClientRoleValue(string name, params ClientRoleMappingValueObject[] mappings) =>
        new()
        {
            RoleName = name,
            Mappings = mappings.ToList()
        };
}
