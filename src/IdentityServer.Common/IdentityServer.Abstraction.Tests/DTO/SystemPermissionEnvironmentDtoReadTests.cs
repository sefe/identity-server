using IdentityServer.Abstraction.DTO.SystemPermissions;
using IdentityServer.Abstraction.Entities.IdentityServerConfig.SystemPermissions;

namespace IdentityServer.Abstraction.Tests.DTO;

[TestFixture]
public class SystemPermissionEnvironmentDtoReadTests
{
    [TestCase(0, 0, false)]
    [TestCase(1, 0, true)]
    [TestCase(0, 1, true)]
    [TestCase(5, 3, true)]
    public void IsInUse_WithVariousCounts_ReturnsExpectedResult(int clientCount, int apiResourceCount, bool expectedResult)
    {
        // Arrange
        var sut = new SystemPermissionEnvironmentDtoRead
        {
            Environment = SystemPermissionEnvironmentNames.Development,
            ClientCount = clientCount,
            ApiResourceCount = apiResourceCount
        };

        // Act & Assert
        Assert.That(sut.IsInUse, Is.EqualTo(expectedResult));
    }

    [TestCase(0, 0, 0)]
    [TestCase(5, 0, 5)]
    [TestCase(0, 7, 7)]
    [TestCase(5, 7, 12)]
    public void TotalRegistrations_WithVariousCounts_ReturnsExpectedSum(int clientCount, int apiResourceCount, int expectedTotal)
    {
        // Arrange
        var sut = new SystemPermissionEnvironmentDtoRead
        {
            Environment = SystemPermissionEnvironmentNames.Development,
            ClientCount = clientCount,
            ApiResourceCount = apiResourceCount
        };

        // Act & Assert
        Assert.That(sut.TotalRegistrations, Is.EqualTo(expectedTotal));
    }

    [TestCase("TestPermission", SystemPermissionEnvironmentNames.Development, "TestPermission (Development)")]
    [TestCase("", SystemPermissionEnvironmentNames.Production, " (Production)")]
    [TestCase("MyPermission", SystemPermissionEnvironmentNames.Integration, "MyPermission (Integration)")]
    public void DisplayName_WithVariousInputs_ReturnsFormattedString(string permissionName, string environment, string expectedDisplayName)
    {
        // Arrange
        var sut = new SystemPermissionEnvironmentDtoRead
        {
            Environment = environment,
            SystemPermissionName = permissionName
        };

        // Act & Assert
        Assert.That(sut.DisplayName, Is.EqualTo(expectedDisplayName));
    }

    [Test]
    public void Owners_OnNoPermissions_ReturnsEmptyString()
    {
        // Arrange
        var sut = new SystemPermissionEnvironmentDtoRead
        {
            Environment = SystemPermissionEnvironmentNames.Development,
            Permissions = new List<SystemPermissionRoleDtoRead>()
        };

        // Act & Assert
        Assert.That(sut.Owners, Is.Empty);
    }

    [Test]
    public void Owners_OnNoWriterRoles_ReturnsEmptyString()
    {
        // Arrange
        var sut = new SystemPermissionEnvironmentDtoRead
        {
            Environment = SystemPermissionEnvironmentNames.Development,
            Permissions = new List<SystemPermissionRoleDtoRead>
            {
                new() {
                    OId = "user1",
                    Name = "User One",
                    RoleType = SystemPermissionRoleType.Reader
                },
                new() {
                    OId = "user2",
                    Name = "User Two",
                    RoleType = SystemPermissionRoleType.Reader
                }
            }
        };

        // Act & Assert
        Assert.That(sut.Owners, Is.Empty);
    }

    [Test]
    public void Owners_OnSingleWriterRole_ReturnsWriterName()
    {
        // Arrange
        var sut = new SystemPermissionEnvironmentDtoRead
        {
            Environment = SystemPermissionEnvironmentNames.Development,
            Permissions = new List<SystemPermissionRoleDtoRead>
            {
                new() {
                    OId = "user1",
                    Name = "Alice",
                    RoleType = SystemPermissionRoleType.Writer
                }
            }
        };

        // Act & Assert
        Assert.That(sut.Owners, Is.EqualTo("Alice"));
    }

    [Test]
    public void Owners_OnMultipleWriterRoles_ReturnsCommaSeparatedSortedNames()
    {
        // Arrange
        var sut = new SystemPermissionEnvironmentDtoRead
        {
            Environment = SystemPermissionEnvironmentNames.Development,
            Permissions = new List<SystemPermissionRoleDtoRead>
            {
                new() {
                    OId = "user1",
                    Name = "Charlie",
                    RoleType = SystemPermissionRoleType.Writer
                },
                new() {
                    OId = "user2",
                    Name = "Alice",
                    RoleType = SystemPermissionRoleType.Writer
                },
                new() {
                    OId = "user3",
                    Name = "Bob",
                    RoleType = SystemPermissionRoleType.Writer
                }
            }
        };

        // Act & Assert
        Assert.That(sut.Owners, Is.EqualTo("Alice, Bob, Charlie"));
    }

    [Test]
    public void Owners_OnMixedRoles_ReturnsOnlyWriterNames()
    {
        // Arrange
        var sut = new SystemPermissionEnvironmentDtoRead
        {
            Environment = SystemPermissionEnvironmentNames.Development,
            Permissions = new List<SystemPermissionRoleDtoRead>
            {
                new() {
                    OId = "user1",
                    Name = "Alice",
                    RoleType = SystemPermissionRoleType.Writer
                },
                new() {
                    OId = "user2",
                    Name = "Bob",
                    RoleType = SystemPermissionRoleType.Reader
                },
                new() {
                    OId = "user3",
                    Name = "Charlie",
                    RoleType = SystemPermissionRoleType.Writer
                }
            }
        };

        // Act & Assert
        Assert.That(sut.Owners, Is.EqualTo("Alice, Charlie"));
    }

    [Test]
    public void GetOwners_OnNoPermissions_ReturnsEmptyArray()
    {
        // Arrange
        var sut = new SystemPermissionEnvironmentDtoRead
        {
            Environment = SystemPermissionEnvironmentNames.Development,
            Permissions = new List<SystemPermissionRoleDtoRead>()
        };

        // Act
        var result = sut.GetOwners();

        // Assert
        Assert.That(result, Is.Empty);
    }

    [Test]
    public void GetOwners_OnNoWriterRoles_ReturnsEmptyArray()
    {
        // Arrange
        var sut = new SystemPermissionEnvironmentDtoRead
        {
            Environment = SystemPermissionEnvironmentNames.Development,
            Permissions = new List<SystemPermissionRoleDtoRead>
            {
                new() {
                    OId = "user1",
                    Name = "Alice",
                    RoleType = SystemPermissionRoleType.Reader
                },
                new() {
                    OId = "user2",
                    Name = "Bob",
                    RoleType = SystemPermissionRoleType.None
                }
            }
        };

        // Act
        var result = sut.GetOwners();

        // Assert
        Assert.That(result, Is.Empty);
    }

    [Test]
    public void GetOwners_OnSingleWriterRole_ReturnsSingleElementArray()
    {
        // Arrange
        var sut = new SystemPermissionEnvironmentDtoRead
        {
            Environment = SystemPermissionEnvironmentNames.Development,
            Permissions = new List<SystemPermissionRoleDtoRead>
            {
                new() {
                    OId = "user1",
                    Name = "Alice",
                    RoleType = SystemPermissionRoleType.Writer
                }
            }
        };

        // Act
        var result = sut.GetOwners();

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result, Has.Length.EqualTo(1));
            Assert.That(result[0], Is.EqualTo("Alice"));
        }
    }

    [Test]
    public void GetOwners_OnMultipleWriterRoles_ReturnsSortedArray()
    {
        // Arrange
        var sut = new SystemPermissionEnvironmentDtoRead
        {
            Environment = SystemPermissionEnvironmentNames.Development,
            Permissions = new List<SystemPermissionRoleDtoRead>
            {
                new() {
                    OId = "user1",
                    Name = "Charlie",
                    RoleType = SystemPermissionRoleType.Writer
                },
                new() {
                    OId = "user2",
                    Name = "Alice",
                    RoleType = SystemPermissionRoleType.Writer
                },
                new() {
                    OId = "user3",
                    Name = "Bob",
                    RoleType = SystemPermissionRoleType.Writer
                }
            }
        };

        // Act
        var result = sut.GetOwners();

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result, Has.Length.EqualTo(3));
            Assert.That(result[0], Is.EqualTo("Alice"));
            Assert.That(result[1], Is.EqualTo("Bob"));
            Assert.That(result[2], Is.EqualTo("Charlie"));
        }
    }

    [Test]
    public void GetOwners_OnMixedRoles_ReturnsOnlyWriterNamesInSortedArray()
    {
        // Arrange
        var sut = new SystemPermissionEnvironmentDtoRead
        {
            Environment = SystemPermissionEnvironmentNames.Development,
            Permissions = new List<SystemPermissionRoleDtoRead>
            {
                new() {
                    OId = "user1",
                    Name = "David",
                    RoleType = SystemPermissionRoleType.Reader
                },
                new() {
                    OId = "user2",
                    Name = "Charlie",
                    RoleType = SystemPermissionRoleType.Writer
                },
                new() {
                    OId = "user3",
                    Name = "Alice",
                    RoleType = SystemPermissionRoleType.Writer
                },
                new() {
                    OId = "user4",
                    Name = "Eve",
                    RoleType = SystemPermissionRoleType.None
                },
                new() {
                    OId = "user5",
                    Name = "Bob",
                    RoleType = SystemPermissionRoleType.Writer
                }
            }
        };

        // Act
        var result = sut.GetOwners();

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result, Has.Length.EqualTo(3));
            Assert.That(result[0], Is.EqualTo("Alice"));
            Assert.That(result[1], Is.EqualTo("Bob"));
            Assert.That(result[2], Is.EqualTo("Charlie"));
        }
    }
}
