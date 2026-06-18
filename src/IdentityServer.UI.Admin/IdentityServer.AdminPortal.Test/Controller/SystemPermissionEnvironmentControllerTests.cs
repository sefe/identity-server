using Microsoft.AspNetCore.Mvc;
using Microsoft.Extensions.DependencyInjection;
using Telerik.DataSource;
using IdentityServer.Abstraction.DTO.SystemPermissions;
using IdentityServer.Abstraction.Entities.IdentityServerConfig.SystemPermissions;
using IdentityServer.Abstraction.Exceptions;
using IdentityServer.AdminPortal.Server.Controllers;
using IdentityServer.AdminPortal.Test.Extensions;
using IdentityServer.Tests.Common;

namespace IdentityServer.AdminPortal.Test.Controller;

public class SystemPermissionEnvironmentControllerTests : ControllerTestBase
{
    private readonly SystemPermissionUtility _permissionUtil = new();
    private ClientController _clientController;
    private ApiResourceController _apiResourceController;
    private SystemPermissionEnvironmentController _envController;

    [SetUp]
    public void Setup()
    {
        var provider = IoC.GetProvider(sc =>
        {
            _permissionUtil.AddToServiceCollection(sc);
            sc.AddScoped<ClientController>();
            sc.AddScoped<ApiResourceController>();
            sc.AddScoped<SystemPermissionEnvironmentController>();
        });

        _permissionUtil.Setup(provider);

        _clientController = provider.GetRequiredService<ClientController>();
        _apiResourceController = provider.GetRequiredService<ApiResourceController>();
        _envController = provider.GetRequiredService<SystemPermissionEnvironmentController>();
    }

    [Test]
    [TestCaseSource(typeof(SystemPermissionRelationshipTestCases), nameof(SystemPermissionRelationshipTestCases.SystemPermissionCreateUnboundData))]
    public async Task CreateEnvironment_WithWrongParent_Fails(string userName, SystemPermissionRoleType assignment)
    {
        // Arrange
        // permission 1 -> env1 -> client 1
        var user = TestUser.Get(userName);
        var nonExistingPermissionId = Random.Shared.Next(1000, int.MaxValue);

        var sp = await _permissionUtil.CreatePermission(TestUser.SuperUser, SystemPermissionUtility.GetNewSystemPermission(), _permissionUtil.DefaultEnvironments);
        if (assignment != SystemPermissionRoleType.None)
        {
            await _permissionUtil.AssignPermissionToUser(user, sp, sp.Environments[0].Environment, assignment);
        }

        var env = new SystemPermissionEnvironmentDtoCreate
        {
            Environment = SystemPermissionEnvironmentNames.EnvironmentNames.Except(_permissionUtil.DefaultEnvironments).First(),
            SystemPermissionId = nonExistingPermissionId
        };

        // Act & Assert
        Assert.ThrowsAsync<EntityReferenceException>(() => _envController.Call_CreateSystemPermissionEnvironmentAsync(env, user));
    }

    [Test]
    public async Task CreateEnvironment_WithDuplicateName_Fails()
    {
        // Arrange
        var sp = await _permissionUtil.CreatePermission(TestUser.SuperUser, SystemPermissionUtility.GetNewSystemPermission(), _permissionUtil.DefaultEnvironments);
        var env = new SystemPermissionEnvironmentDtoCreate
        {
            Environment = _permissionUtil.DefaultEnvironments[0],
            SystemPermissionId = sp.Id
        };

        // Act & Assert
        Assert.ThrowsAsync<EntityAlreadyExistsException>(() => _envController.Call_CreateSystemPermissionEnvironmentAsync(env, TestUser.SuperUser));
    }

    [Test]
    public async Task DeleteSystemPermissionEnvironmentByIdAsync_ReturnsNotFound_WhenItemDoesNotExist()
    {
        // Arrange
        var user = TestUser.SuperUser;
        SetControllerContext(_envController, user);
        // Act
        var result = await _envController.DeleteSystemPermissionEnvironmentByIdAsync(99999);
        // Assert
        Assert.That(result.Result, Is.InstanceOf<NotFoundResult>());
    }

    [Test]
    public async Task DeleteSystemPermissionEnvironmentByIdAsync_ReturnsOk_WhenItemDeleted()
    {
        // Arrange
        var user = TestUser.SuperUser;
        var sp = await _permissionUtil.CreatePermission(user, SystemPermissionUtility.GetNewSystemPermission(), _permissionUtil.DefaultEnvironments);
        var env = sp.Environments[0];
        // Act
        var result = await _envController.Call_DeleteSystemPermissionEnvironmentByIdAsync(env.Id, user);
        // Assert
        Assert.That(result.Value, Is.EqualTo(env.Id));
    }

    [Test]
    public async Task DeleteSystemPermissionEnvironment_WithNestedPermissions_ExecutesSuccessfullyAndUpdatesAuditFields()
    {
        // Arrange
        var sp = await _permissionUtil.CreatePermission(TestUser.SuperUser, SystemPermissionUtility.GetNewSystemPermission(), _permissionUtil.StandardEnvironments);
        var envToDelete = sp.Environments[0];

        sp = await _permissionUtil.AssignPermissionToUser(TestUser.Contributor, sp, envToDelete.Environment, SystemPermissionRoleType.Writer);
        _ = await _permissionUtil.AssignPermissionToUser(TestUser.Reader, sp, envToDelete.Environment, SystemPermissionRoleType.Reader);

        // Act
        var result = await _envController.Call_DeleteSystemPermissionEnvironmentByIdAsync(envToDelete.Id, TestUser.SuperUser);

        // Assert - Verify deletion was successful
        Assert.That(result, Is.EqualTo(envToDelete.Id));

        var response = await _envController.GetSystemPermissionEnvironmentByIdAsync(envToDelete.Id);
        Assert.That(response.Result, Is.TypeOf<NotFoundResult>());
    }

    [Test]
    [TestCaseSource(typeof(SystemPermissionRelationshipTestCases), nameof(SystemPermissionRelationshipTestCases.DeleteSystemPermissionWithRelationship))]
    public async Task DeleteSystemPermissionEnvironment_WithAssignedClient_Fails(string userName, SystemPermissionRoleType assignment, Type exceptionType)
    {
        // Arrange
        // permission 1 -> env1 -> api 1
        var user = TestUser.Get(userName);

        var sp = await _permissionUtil.CreatePermission(TestUser.SuperUser, SystemPermissionUtility.GetNewSystemPermission(), _permissionUtil.StandardEnvironments);
        var envToDelete = sp.Environments[0];
        if (assignment != SystemPermissionRoleType.None)
        {
            await _permissionUtil.AssignPermissionToUser(TestUser.Contributor, sp, envToDelete.Environment, assignment);
        }

        await _clientController.Call_CreateClientAsync(ClientControllerExtensions.GetDefaultClient(envToDelete.Id), Admin);

        // Act & Assert
        Assert.ThrowsAsync(Is.TypeOf(exceptionType), () => _envController.Call_DeleteSystemPermissionEnvironmentByIdAsync(envToDelete.Id, user));
    }

    [Test]
    [TestCaseSource(typeof(SystemPermissionRelationshipTestCases), nameof(SystemPermissionRelationshipTestCases.DeleteSystemPermissionWithRelationship))]
    public async Task DeleteSystemPermissionEnvironment_WithAssignedApi_Fails(string userName, SystemPermissionRoleType assignment, Type exceptionType)
    {
        // Arrange
        // permission 1 -> env1 -> api 1
        var user = TestUser.Get(userName);

        var sp = await _permissionUtil.CreatePermission(TestUser.SuperUser, SystemPermissionUtility.GetNewSystemPermission(), _permissionUtil.StandardEnvironments);
        var envToDelete = sp.Environments[0];
        if (assignment != SystemPermissionRoleType.None)
        {
            await _permissionUtil.AssignPermissionToUser(TestUser.Contributor, sp, envToDelete.Environment, assignment);
        }

        await _apiResourceController.Call_CreateApiResourceAsync(ApiResourceControllerExtensions.GetDefaultApiResource(envToDelete.Id), Admin);

        // Act & Assert
        Assert.ThrowsAsync(Is.TypeOf(exceptionType), () => _envController.Call_DeleteSystemPermissionEnvironmentByIdAsync(envToDelete.Id, user));
    }

    [Test]
    [TestCaseSource(typeof(SystemPermissionRelationshipTestCases), nameof(SystemPermissionRelationshipTestCases.DeleteSystemPermissionNoRelationship))]
    public async Task DeleteSystemPermissionEnvironment_WhenNoRelatedEntities_Success(string userName, SystemPermissionRoleType assignment, Type exceptionType)
    {
        // Arrange
        // permission 1 -> env1,env2
        var user = TestUser.Get(userName);

        var sp = await _permissionUtil.CreatePermission(TestUser.SuperUser, SystemPermissionUtility.GetNewSystemPermission(), _permissionUtil.DefaultEnvironments);
        var envToDelete = sp.Environments[^1];

        if (assignment != SystemPermissionRoleType.None)
        {
            sp = await _permissionUtil.AssignPermissionToUser(user, sp, envToDelete.Environment, assignment);
        }

        // Act
        if (exceptionType == null)
        {
            var result = await _envController.Call_DeleteSystemPermissionEnvironmentByIdAsync(envToDelete.Id, user);
            Assert.That(result, Is.EqualTo(envToDelete.Id));
        }
        else
        {
            Assert.ThrowsAsync(Is.TypeOf(exceptionType), () => _envController.Call_DeleteSystemPermissionEnvironmentByIdAsync(sp.Id, user));
        }
    }

    [Test]
    public async Task Get_Environment_Contacts_ReturnsData_When_NoAccessToEnvironment()
    {
        // Arrange
        // permission 1 -> env1
        // user who created environment is added as writer, so it should appear in contacts.
        // user who has no access should be able to see contacts of any environment or system permission
        var userCreator = TestUser.SuperUser;
        var userWithNoAccess = TestUser.Reader;
        var sp = await _permissionUtil.CreatePermission(userCreator, SystemPermissionUtility.GetNewSystemPermission(), _permissionUtil.DefaultEnvironments);

        // Act
        var contacts = await _envController.Call_GetSystemPermissionEnvironmentContactsByIdAsync(sp.Environments[0].Id, userWithNoAccess);

        // Assert
        Assert.That(contacts, Is.EquivalentTo(new string[] { userCreator.Identity.Name }));
    }

    /// <summary>
    /// This method is different from other DataSourceRequest actions, because there's filtering logic on the repository level.
    /// </summary>
    /// <returns>Test result</returns>
    [Test]
    public async Task Get_Environment_Paged_Returns_Environments_With_Writer_Assignment_Only()
    {
        // Arrange
        var user = TestUser.Reader;
        var sp = await _permissionUtil.CreatePermission(TestUser.SuperUser, SystemPermissionUtility.GetNewSystemPermission(), _permissionUtil.StandardEnvironments);
        sp = await _permissionUtil.AssignPermissionToUser(user, sp, sp.Environments[0].Environment, SystemPermissionRoleType.Writer);
        sp = await _permissionUtil.AssignPermissionToUser(user, sp, sp.Environments[1].Environment, SystemPermissionRoleType.Reader);

        var req = new DataSourceRequest
        {
            Page = 1,
            PageSize = 10,
        };

        // Act
        var page = await _envController.Call_GetSystemPermissionEnvironmentsPagedAsync(req, user);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(page.TotalItemCount, Is.EqualTo(1));
            Assert.That(page.CurrentPageData[0].Id, Is.EqualTo(sp.Environments[0].Id));
        }
    }

    [Test]
    public async Task GetSystemPermissionEnvironmentByIdAsync_ReturnsNotFound_WhenItemDoesNotExist()
    {
        // Arrange
        var user = TestUser.SuperUser;
        SetControllerContext(_envController, user);
        // Act
        var result = await _envController.GetSystemPermissionEnvironmentByIdAsync(99999);

        // Assert
        Assert.That(result.Result, Is.InstanceOf<NotFoundResult>());
    }

    [Test]
    public async Task GetSystemPermissionEnvironmentByIdAsync_ReturnsOk_WhenItemExists()
    {
        // Arrange
        var user = TestUser.SuperUser;
        var sp = await _permissionUtil.CreatePermission(user, SystemPermissionUtility.GetNewSystemPermission(), _permissionUtil.DefaultEnvironments);
        var env = sp.Environments[0];

        // Act
        var result = await _envController.Call_GetSystemPermissionEnvironmentByIdAsync(env.Id, user);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result.Id, Is.EqualTo(env.Id));
            Assert.That(result.Environment, Is.EqualTo(env.Environment));
        }
    }
}
