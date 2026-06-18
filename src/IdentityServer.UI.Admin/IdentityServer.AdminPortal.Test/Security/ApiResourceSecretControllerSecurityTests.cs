using Microsoft.Extensions.DependencyInjection;
using IdentityServer.Abstraction.DTO.ApiResources;
using IdentityServer.Abstraction.Entities.IdentityServerConfig.SystemPermissions;
using IdentityServer.Abstraction.Exceptions;
using IdentityServer.AdminPortal.Server.Controllers;
using IdentityServer.AdminPortal.Test.Controller;
using IdentityServer.AdminPortal.Test.Extensions;

namespace IdentityServer.AdminPortal.Test.Security;

public class ApiResourceSecretControllerSecurityTests : ControllerTestBase
{
    private readonly SystemPermissionUtility _permissionUtil = new();
    private ApiResourcePropertySecretController _apiResourceSecretController;
    private ApiResourceController _apiResourceController;

    [SetUp]
    public void SetupAsync()
    {
        var provider = IoC.GetProvider(sc =>
        {
            _permissionUtil.AddToServiceCollection(sc);
            sc.AddScoped<ApiResourcePropertySecretController>();
            sc.AddScoped<ApiResourceController>();
        });

        _permissionUtil.Setup(provider);

        _apiResourceSecretController = provider.GetRequiredService<ApiResourcePropertySecretController>();
        _apiResourceController = provider.GetRequiredService<ApiResourceController>();

        SetControllerContext(_apiResourceSecretController, Admin);
        SetControllerContext(_apiResourceController, Admin);
    }

    [Test]
    public async Task Add_ApiResourceSecret_AccessibleApiResource()
    {
        // Arrange
        // sp -> env -> apiResource; User with Writer access
        var (permission, apiResource) = await SetupTestDataAsync();
        _ = await _permissionUtil.AssignPermissionToUser(Contributor, permission, SystemPermissionEnvironmentNames.Development, SystemPermissionRoleType.Writer);

        var apiResourceSecret = new ApiResourcePropertySecretDtoCreate { ApiResourceId = apiResource.Id, Description = "secret1", ValidityPeriodYears = 2 };

        // Act
        var result = await _apiResourceSecretController.Call_CreateSecretAsync(apiResourceSecret, Contributor);

        // Assert
        Assert.That(result, Is.Not.Null);
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result.ApiResourceId, Is.EqualTo(apiResource.Id));
            Assert.That(result.Value, Is.Not.Null);
        }
    }

    [Test]
    public async Task Add_ApiResourceSecret_ReadonlyApiResource()
    {
        // Arrange
        // sp -> env -> apiResource; User with Reader access
        var (permission, apiResource) = await SetupTestDataAsync();
        _ = await _permissionUtil.AssignPermissionToUser(Contributor, permission, SystemPermissionEnvironmentNames.Development, SystemPermissionRoleType.Reader);

        var apiResourceSecret = new ApiResourcePropertySecretDtoCreate { ApiResourceId = apiResource.Id, Description = "secret1", ValidityPeriodYears = 2 };

        // Act & Assert
        Assert.ThrowsAsync<EntityAccessException>(() => _apiResourceSecretController.Call_CreateSecretAsync(apiResourceSecret, Contributor));
    }

    [Test]
    public async Task Add_ApiResourceSecret_InaccessibleApiResource()
    {
        // Arrange
        // sp -> env -> apiResource; User with NO access
        var (permission, apiResource) = await SetupTestDataAsync();

        var apiResourceSecret = new ApiResourcePropertySecretDtoCreate { ApiResourceId = apiResource.Id, Description = "secret1", ValidityPeriodYears = 2 };

        // Act & Assert
        Assert.ThrowsAsync<EntityAccessException>(() => _apiResourceSecretController.Call_CreateSecretAsync(apiResourceSecret, Contributor));
    }

    [Test]
    public async Task Delete_ApiResourceSecret_AccessibleApiResource()
    {
        // Arrange
        // sp -> env -> apiResource + secret; User with Writer access
        var (permission, apiResource) = await SetupTestDataAsync();
        var apiResourceSecret = new ApiResourcePropertySecretDtoCreate { ApiResourceId = apiResource.Id, Description = "secret1", ValidityPeriodYears = 2 };
        var createdSecret = await _apiResourceSecretController.Call_CreateSecretAsync(apiResourceSecret, Admin);
        _ = await _permissionUtil.AssignPermissionToUser(Contributor, permission, SystemPermissionEnvironmentNames.Development, SystemPermissionRoleType.Writer);

        // Act
        var result = await _apiResourceSecretController.Call_DeleteSecretAsync(createdSecret.Id, Contributor);

        // Assert
        Assert.That(result, Is.EqualTo(createdSecret.Id));
    }

    [Test]
    public async Task Delete_ApiResourceSecret_ReadonlyApiResource()
    {
        // Arrange
        // sp -> env -> apiResource + secret; User with Reader access
        var (permission, apiResource) = await SetupTestDataAsync();
        var apiResourceSecret = new ApiResourcePropertySecretDtoCreate { ApiResourceId = apiResource.Id, Description = "secret1", ValidityPeriodYears = 2 };
        var createdSecret = await _apiResourceSecretController.Call_CreateSecretAsync(apiResourceSecret, Admin);
        _ = await _permissionUtil.AssignPermissionToUser(Contributor, permission, SystemPermissionEnvironmentNames.Development, SystemPermissionRoleType.Reader);

        // Act & Assert
        Assert.ThrowsAsync<EntityAccessException>(() => _apiResourceSecretController.Call_DeleteSecretAsync(createdSecret.Id, Contributor));
    }

    [Test]
    public async Task Delete_ApiResourceSecret_InaccessibleApiResource()
    {
        // Arrange
        // sp -> env -> apiResource + secret; User with NO access
        var (permission, apiResource) = await SetupTestDataAsync();
        var apiResourceSecret = new ApiResourcePropertySecretDtoCreate { ApiResourceId = apiResource.Id, Description = "secret1", ValidityPeriodYears = 2 };
        var createdSecret = await _apiResourceSecretController.Call_CreateSecretAsync(apiResourceSecret, Admin);

        // Act & Assert
        Assert.ThrowsAsync<EntityAccessException>(() => _apiResourceSecretController.Call_DeleteSecretAsync(createdSecret.Id, Contributor));
    }

    private async Task<(SystemPermission permission, ApiResourceDtoRead apiResource)> SetupTestDataAsync()
    {
        var testPermission = await _permissionUtil.CreatePermission(Admin, SystemPermissionUtility.GetNewSystemPermission(), _permissionUtil.DefaultEnvironments);
        var res = await _apiResourceController.Call_CreateApiResourceAsync(ApiResourceControllerExtensions.GetDefaultApiResource(testPermission.Environments.First().Id), Admin);
        return (testPermission, res);
    }
}
