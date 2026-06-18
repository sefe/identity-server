using IdentityServer.Abstraction.DTO.SystemPermissions;
using IdentityServer.Abstraction.Entities.IdentityServerConfig.SystemPermissions;

namespace IdentityServer.Abstraction.Tests.DTO;

[TestFixture]
public class SystemPermissionDtoReadTests
{
    [Test]
    public void IsInUse_OnNoEnvironments_ReturnsFalse()
    {
        var sut = new SystemPermissionDtoRead
        {
            Name = "1",
            Description = "1",
        };

        Assert.That(sut.IsInUse, Is.False);
    }

    [Test]
    public void IsInUse_OnNoEnvironmentsHaveRegisteredEntities_ReturnsFalse()
    {
        var sut = new SystemPermissionDtoRead
        {
            Name = "1",
            Description = "1",
            Environments = new()
            {
                new SystemPermissionEnvironmentDtoRead
                {
                    Environment = SystemPermissionEnvironmentNames.Development,
                    ClientCount = 0,
                    ApiResourceCount = 0,
                },
                new SystemPermissionEnvironmentDtoRead
                {
                    Environment = SystemPermissionEnvironmentNames.Integration,
                    ClientCount = 0,
                    ApiResourceCount = 0,
                }
            }
        };

        Assert.That(sut.IsInUse, Is.False);
    }

    [Test]
    public void IsInUse_IfAnyEnvironmentHasRegisteredClients_ReturnsTrue()
    {
        var sut = new SystemPermissionDtoRead
        {
            Name = "1",
            Description = "1",
            Environments = new()
            {
                new SystemPermissionEnvironmentDtoRead
                {
                    Environment = SystemPermissionEnvironmentNames.Development,
                    ClientCount = 0,
                    ApiResourceCount = 0,
                },
                new SystemPermissionEnvironmentDtoRead
                {
                    Environment = SystemPermissionEnvironmentNames.Integration,
                    ClientCount = 1,
                    ApiResourceCount = 0,
                }
            }
        };

        Assert.That(sut.IsInUse, Is.True);
    }

    [Test]
    public void IsInUse_IfAnyEnvironmentHasRegisteredApiResources_ReturnsTrue()
    {
        var sut = new SystemPermissionDtoRead
        {
            Name = "1",
            Description = "1",
            Environments = new()
            {
                new SystemPermissionEnvironmentDtoRead
                {
                    Environment = SystemPermissionEnvironmentNames.Development,
                    ClientCount = 0,
                    ApiResourceCount = 0,
                },
                new SystemPermissionEnvironmentDtoRead
                {
                    Environment = SystemPermissionEnvironmentNames.Integration,
                    ClientCount = 0,
                    ApiResourceCount = 1,
                }
            }
        };

        Assert.That(sut.IsInUse, Is.True);
    }
}
