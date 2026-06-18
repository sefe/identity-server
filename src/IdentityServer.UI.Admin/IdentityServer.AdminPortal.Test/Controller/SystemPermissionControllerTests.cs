using Microsoft.AspNetCore.Mvc;
using Microsoft.Extensions.DependencyInjection;
using NSubstitute;
using IdentityServer.Abstraction.Contracts;
using IdentityServer.Abstraction.DTO.SystemPermissions;
using IdentityServer.Abstraction.Entities.IdentityServerConfig.SystemPermissions;
using IdentityServer.Abstraction.Exceptions;
using IdentityServer.AdminPortal.Server.Controllers;
using IdentityServer.AdminPortal.Test.Extensions;
using IdentityServer.Tests.Common;

namespace IdentityServer.AdminPortal.Test.Controller;

public class SystemPermissionControllerTests : ControllerTestBase
{
    private readonly SystemPermissionUtility _permissionUtil = new();
    private ClientController _clientController;
    private ApiResourceController _apiResourceController;
    private SystemPermissionController _systemController;
    private SystemPermissionEnvironmentController _envController;
    private ISystemPermissionAuditService _auditService;

    [SetUp]
    public void Setup()
    {
        var provider = IoC.GetProvider(sc =>
        {
            _permissionUtil.AddToServiceCollection(sc);
            sc.AddScoped<ClientController>();
            sc.AddScoped<ApiResourceController>();
            sc.AddScoped<SystemPermissionController>();
            sc.AddScoped<SystemPermissionEnvironmentController>();
        });

        _permissionUtil.Setup(provider);

        _clientController = provider.GetRequiredService<ClientController>();
        _apiResourceController = provider.GetRequiredService<ApiResourceController>();
        _systemController = provider.GetRequiredService<SystemPermissionController>();
        _envController = provider.GetRequiredService<SystemPermissionEnvironmentController>();
        _auditService = provider.GetRequiredService<ISystemPermissionAuditService>();
    }

    [Test]
    public async Task CreateSystemPermission_IfValid_Succeeds()
    {
        // Arrange
        var spDto = new SystemPermissionDtoCreate()
        {
            Name = "New Permission",
            Description = "Description"
        };

        // Act
        var created = await _systemController.Call_CreateSystemPermissionAsync(spDto, SuperUser);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            // Assert
            Assert.That(created.Id, Is.GreaterThan(0));
            Assert.That(created.Name, Is.EqualTo(spDto.Name));
            Assert.That(created.Description, Is.EqualTo(spDto.Description));
        }
    }

    [Test]
    public async Task CreateSystemPermission_IfDuplicateName_Fails()
    {
        // Arrange
        var sp = await _permissionUtil.CreatePermission(TestUser.SuperUser, SystemPermissionUtility.GetNewSystemPermission(), _permissionUtil.DefaultEnvironments);
        var newSpDto = new Abstraction.DTO.SystemPermissions.SystemPermissionDtoCreate()
        {
            Name = sp.Name,
            Description = sp.Description
        };

        // Act & Assert
        Assert.ThrowsAsync<EntityAlreadyExistsException>(() => _systemController.Call_CreateSystemPermissionAsync(newSpDto, SuperUser));
    }

    [Test]
    public async Task GetSystemPermission_IfValidId_Succeeds()
    {
        // Arrange
        var sp = await _permissionUtil.CreatePermission(TestUser.SuperUser, SystemPermissionUtility.GetNewSystemPermission(), _permissionUtil.DefaultEnvironments);

        // Act
        var spDtoRead = await _systemController.Call_GetSystemPermissionByIdAsync(sp.Id, SuperUser);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            // Assert
            Assert.That(spDtoRead.Id, Is.EqualTo(sp.Id));
            Assert.That(spDtoRead.Name, Is.EqualTo(sp.Name));
            Assert.That(spDtoRead.Description, Is.EqualTo(sp.Description));
        }
    }

    [Test]
    public async Task GetSystemPermission_IfInvalidId_Fails()
    {
        // Arrange
        SetControllerContext(_systemController, SuperUser);

        // Act
        var result = await _systemController.GetSystemPermissionByIdAsync(99999);

        // Assert
        Assert.That(result.Result, Is.InstanceOf<NotFoundResult>());
    }

    [Test]
    public async Task GetSystemPermission_ReturnsLastUpdatedTimestamp()
    {
        // Arrange
        var spDto = new SystemPermissionDtoCreate()
        {
            Name = "New Permission",
            Description = "Description"
        };
        var created = await _systemController.Call_CreateSystemPermissionAsync(spDto, SuperUser);
        var ts = DateTime.UtcNow;
        _auditService.GetLastModifiedByIdAsync(created.Id).Returns(new EntityLastModifiedData
        {
            Id = created.Id,
            LastModified = ts,
            Reason = "Environments"
        });

        // Act
        var result = await _systemController.Call_GetSystemPermissionByIdAsync(created.Id, SuperUser);

        // Assert
        Assert.That(result.Updated, Is.EqualTo(ts));
    }

    [Test]
    public async Task DeleteSystemPermission_WithNestedEntities_ExecutesSuccessfullyAndUpdatesAuditFields()
    {
        // Arrange
        var sp = await _permissionUtil.CreatePermission(TestUser.SuperUser, SystemPermissionUtility.GetNewSystemPermission(), _permissionUtil.StandardEnvironments);

        sp = await _permissionUtil.AssignPermissionToUser(TestUser.Contributor, sp, sp.Environments[0].Environment, SystemPermissionRoleType.Writer);
        sp = await _permissionUtil.AssignPermissionToUser(TestUser.Reader, sp, sp.Environments[1].Environment, SystemPermissionRoleType.Reader);

        // Act
        var result = await _systemController.Call_DeleteSystemPermissionByIdAsync(sp.Id, SuperUser);

        // Assert
        Assert.That(result, Is.EqualTo(sp.Id));

        var response = await _systemController.GetSystemPermissionByIdAsync(sp.Id);
        Assert.That(response.Result, Is.TypeOf<NotFoundResult>());
    }

    [Test]
    [TestCaseSource(typeof(SystemPermissionRelationshipTestCases), nameof(SystemPermissionRelationshipTestCases.DeleteSystemPermissionWithRelationship))]
    public async Task DeleteSystemPermission_WithAssignedClients_Fails(string userName, SystemPermissionRoleType assignment, Type exceptionType)
    {
        // Arrange
        // permission 1 -> env1 -> client 1
        var user = TestUser.Get(userName);

        var sp = await _permissionUtil.CreatePermission(TestUser.SuperUser, SystemPermissionUtility.GetNewSystemPermission(), _permissionUtil.DefaultEnvironments);
        if (assignment != SystemPermissionRoleType.None)
        {
            sp = await _permissionUtil.AssignPermissionToUser(user, sp, sp.Environments[0].Environment, assignment);
        }
        await _clientController.Call_CreateClientAsync(ClientControllerExtensions.GetDefaultClient(sp.Environments[0].Id), Admin);

        // Act & Assert
        Assert.ThrowsAsync(Is.TypeOf(exceptionType), () => _systemController.Call_DeleteSystemPermissionByIdAsync(sp.Id, user));
    }

    [Test]
    [TestCaseSource(typeof(SystemPermissionRelationshipTestCases), nameof(SystemPermissionRelationshipTestCases.DeleteSystemPermissionWithRelationship))]
    public async Task DeleteSystemPermission_WithAssignedApi_Fails(string userName, SystemPermissionRoleType assignment, Type exceptionType)
    {
        // Arrange
        // permission 1 -> env1 -> api 1
        var user = TestUser.Get(userName);

        var sp = await _permissionUtil.CreatePermission(TestUser.SuperUser, SystemPermissionUtility.GetNewSystemPermission(), _permissionUtil.DefaultEnvironments);
        if (assignment != SystemPermissionRoleType.None)
        {
            sp = await _permissionUtil.AssignPermissionToUser(user, sp, sp.Environments[0].Environment, assignment);
        }

        await _apiResourceController.Call_CreateApiResourceAsync(ApiResourceControllerExtensions.GetDefaultApiResource(sp.Environments[0].Id), Admin);

        // Act & Assert
        Assert.ThrowsAsync(Is.TypeOf(exceptionType), () => _systemController.Call_DeleteSystemPermissionByIdAsync(sp.Id, user));
    }

    [Test]
    [TestCaseSource(typeof(SystemPermissionRelationshipTestCases), nameof(SystemPermissionRelationshipTestCases.DeleteSystemPermissionNoRelationship))]
    public async Task DeleteSystemPermission_WhenNoRelatedEntities(string userName, SystemPermissionRoleType assignment, Type exceptionType)
    {
        // Arrange
        // permission 1 -> env1,env2
        var user = TestUser.Get(userName);

        var sp = await _permissionUtil.CreatePermission(TestUser.SuperUser, SystemPermissionUtility.GetNewSystemPermission(), _permissionUtil.DefaultEnvironments);

        if (assignment != SystemPermissionRoleType.None)
        {
            sp = await _permissionUtil.AssignPermissionToUser(user, sp, sp.Environments[0].Environment, assignment);
        }

        // Act & Assert
        if (exceptionType == null)
        {
            var result = await _systemController.Call_DeleteSystemPermissionByIdAsync(sp.Id, user);
            Assert.That(result, Is.EqualTo(sp.Id));
        }
        else
        {
            Assert.ThrowsAsync(Is.TypeOf(exceptionType), () => _systemController.Call_DeleteSystemPermissionByIdAsync(sp.Id, user));
        }
    }

    [Test]
    public async Task GetSystemPermissionsPagedAsync_WithoutAuditData_ReturnsPermissionsWithOriginalUpdatedValue()
    {
        // Arrange
        var sp1 = await _permissionUtil.CreatePermission(TestUser.SuperUser, SystemPermissionUtility.GetNewSystemPermission(), _permissionUtil.DefaultEnvironments);
        var sp2 = await _permissionUtil.CreatePermission(TestUser.SuperUser, SystemPermissionUtility.GetNewSystemPermission(), _permissionUtil.DefaultEnvironments);

        var ts = DateTime.UtcNow;
        await _systemController.Call_UpdateSystemPermissionAsync(new SystemPermissionDtoUpdate
        {
            Id = sp2.Id,
            Description = "Updated Description 2"
        }, SuperUser);

        // Act
        var permissions = await _systemController.Call_GetSystemPermissionsPagedAsync(SuperUser);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(permissions, Has.Count.EqualTo(2));
            Assert.That(permissions.First(p => p.Id == sp1.Id).Updated, Is.Null);
            Assert.That(permissions.First(p => p.Id == sp2.Id).Updated, Is.GreaterThanOrEqualTo(ts).And.LessThanOrEqualTo(DateTime.UtcNow));
        }
    }

    [Test]
    public async Task GetSystemPermissionsPagedAsync_WithAuditData_ReturnsSystemPermissionsWithAuditTimestamps()
    {
        // Arrange
        var sp1 = await _permissionUtil.CreatePermission(TestUser.SuperUser, SystemPermissionUtility.GetNewSystemPermission(), _permissionUtil.DefaultEnvironments);
        var sp2 = await _permissionUtil.CreatePermission(TestUser.SuperUser, SystemPermissionUtility.GetNewSystemPermission(), _permissionUtil.DefaultEnvironments);

        var ts1 = DateTime.UtcNow.AddMinutes(-10);
        var ts2 = DateTime.UtcNow.AddMinutes(-5);

        var lastModifiedDict = new Dictionary<int, EntityLastModifiedData>
        {
            { sp1.Id, new EntityLastModifiedData { Id = sp1.Id, LastModified = ts1 } },
            { sp2.Id, new EntityLastModifiedData { Id = sp2.Id, LastModified = ts2 } }
        };

        _auditService.GetLastModifiedByIdAsync(Arg.Any<List<int>>()).Returns(lastModifiedDict);

        // Act
        var permissions = await _systemController.Call_GetSystemPermissionsPagedAsync(SuperUser);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(permissions, Has.Count.EqualTo(2));
            Assert.That(permissions.FirstOrDefault(p => p.Id == sp1.Id)?.Updated, Is.EqualTo(ts1));
            Assert.That(permissions.FirstOrDefault(p => p.Id == sp2.Id)?.Updated, Is.EqualTo(ts2));
        }
    }

    [Test]
    public async Task GetSystemPermissionsPagedAsync_WithNoRegistrations_ReturnsTotalRegistrationsAsZero()
    {
        // Arrange
        var sp = await _permissionUtil.CreatePermission(TestUser.SuperUser, SystemPermissionUtility.GetNewSystemPermission(), _permissionUtil.DefaultEnvironments);

        // Act
        var permissions = await _systemController.Call_GetSystemPermissionsPagedAsync(SuperUser);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(permissions, Has.Count.EqualTo(1));
            Assert.That(permissions.First().Id, Is.EqualTo(sp.Id));
            Assert.That(permissions.First().TotalRegistrations, Is.Zero);
        }
    }

    [Test]
    public async Task GetSystemPermissionsPagedAsync_WithClientRegistrations_ReturnsTotalRegistrationsCount()
    {
        // Arrange
        var sp = await _permissionUtil.CreatePermission(TestUser.SuperUser, SystemPermissionUtility.GetNewSystemPermission(), _permissionUtil.DefaultEnvironments);
        await _clientController.Call_CreateClientAsync(ClientControllerExtensions.GetDefaultClient(sp.Environments[0].Id), Admin);
        await _clientController.Call_CreateClientAsync(ClientControllerExtensions.GetDefaultClient(sp.Environments[0].Id), Admin);

        // Act
        var permissions = await _systemController.Call_GetSystemPermissionsPagedAsync(SuperUser);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(permissions, Has.Count.EqualTo(1));
            Assert.That(permissions.First().Id, Is.EqualTo(sp.Id));
            Assert.That(permissions.First().TotalRegistrations, Is.EqualTo(2));
        }
    }

    [Test]
    public async Task GetSystemPermissionsPagedAsync_WithApiResourceRegistrations_ReturnsTotalRegistrationsCount()
    {
        // Arrange
        var sp = await _permissionUtil.CreatePermission(TestUser.SuperUser, SystemPermissionUtility.GetNewSystemPermission(), _permissionUtil.DefaultEnvironments);
        await _apiResourceController.Call_CreateApiResourceAsync(ApiResourceControllerExtensions.GetDefaultApiResource(sp.Environments[0].Id), Admin);
        await _apiResourceController.Call_CreateApiResourceAsync(ApiResourceControllerExtensions.GetDefaultApiResource(sp.Environments[0].Id), Admin);

        // Act
        var permissions = await _systemController.Call_GetSystemPermissionsPagedAsync(SuperUser);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(permissions, Has.Count.EqualTo(1));
            Assert.That(permissions.First().Id, Is.EqualTo(sp.Id));
            Assert.That(permissions.First().TotalRegistrations, Is.EqualTo(2));
        }
    }

    [Test]
    public async Task GetSystemPermissionsPagedAsync_WithMixedRegistrations_ReturnsCombinedTotalRegistrationsCount()
    {
        // Arrange
        var sp = await _permissionUtil.CreatePermission(TestUser.SuperUser, SystemPermissionUtility.GetNewSystemPermission(), _permissionUtil.DefaultEnvironments);
        await _clientController.Call_CreateClientAsync(ClientControllerExtensions.GetDefaultClient(sp.Environments[0].Id), Admin);
        await _apiResourceController.Call_CreateApiResourceAsync(ApiResourceControllerExtensions.GetDefaultApiResource(sp.Environments[0].Id), Admin);

        // Act
        var permissions = await _systemController.Call_GetSystemPermissionsPagedAsync(SuperUser);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(permissions, Has.Count.EqualTo(1));
            Assert.That(permissions.First().Id, Is.EqualTo(sp.Id));
            Assert.That(permissions.First().TotalRegistrations, Is.EqualTo(2));
        }
    }

    [Test]
    public async Task GetSystemPermissionsPagedAsync_WithMultiplePermissions_ReturnsCorrectRegistrationsForEach()
    {
        // Arrange
        var sp1 = await _permissionUtil.CreatePermission(TestUser.SuperUser, SystemPermissionUtility.GetNewSystemPermission(), _permissionUtil.DefaultEnvironments);
        var sp2 = await _permissionUtil.CreatePermission(TestUser.SuperUser, SystemPermissionUtility.GetNewSystemPermission(), _permissionUtil.DefaultEnvironments);

        // Add 2 clients to sp1
        await _clientController.Call_CreateClientAsync(ClientControllerExtensions.GetDefaultClient(sp1.Environments[0].Id), Admin);
        await _clientController.Call_CreateClientAsync(ClientControllerExtensions.GetDefaultClient(sp1.Environments[0].Id), Admin);

        // Add 1 API resource to sp2
        await _apiResourceController.Call_CreateApiResourceAsync(ApiResourceControllerExtensions.GetDefaultApiResource(sp2.Environments[0].Id), Admin);

        // Act
        var permissions = await _systemController.Call_GetSystemPermissionsPagedAsync(SuperUser);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(permissions, Has.Count.EqualTo(2));
            Assert.That(permissions.First(p => p.Id == sp1.Id).TotalRegistrations, Is.EqualTo(2));
            Assert.That(permissions.First(p => p.Id == sp2.Id).TotalRegistrations, Is.EqualTo(1));
        }
    }
}

