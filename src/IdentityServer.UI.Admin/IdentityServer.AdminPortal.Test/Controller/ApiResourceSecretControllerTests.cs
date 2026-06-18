using Duende.IdentityServer.Models;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Extensions.DependencyInjection;
using NSubstitute;
using IdentityServer.Abstraction.Contracts;
using IdentityServer.Abstraction.Exceptions;
using IdentityServer.AdminPortal.Server.Controllers;
using IdentityServer.AdminPortal.Test.Extensions;
using IdentityServer.Data.DuendeEntityExtensions;
using IdentityServer.Tests.Common;
using DataEntities = Duende.IdentityServer.EntityFramework.Entities;

namespace IdentityServer.AdminPortal.Test.Controller;

public class ApiResourceSecretControllerTests : ControllerTestBase
{
    private ApiResourceController _apiResourceController;
    private ApiResourcePropertySecretController _secretController;
    private IStorage<ApiResourceSecretExt> _apiResourceSecretStorage;
    private ICache<DataEntities.ApiResource> _apiCache;

    [SetUp]
    public async Task Setup()
    {
        _apiCache = Substitute.For<ICache<DataEntities.ApiResource>>();

        var provider = IoC.GetProvider(sc =>
        {
            sc.AddScoped<ApiResourceController>();
            sc.AddScoped<ApiResourcePropertySecretController>();
            sc.ReplaceWithInstance(EverythingIsAllowed);
            sc.ReplaceWithInstance(_apiCache);
        });

        await Setup(provider);

        _apiResourceController = provider.GetRequiredService<ApiResourceController>();
        _secretController = provider.GetRequiredService<ApiResourcePropertySecretController>();
        _apiResourceSecretStorage = provider.GetRequiredService<IStorage<ApiResourceSecretExt>>();
    }

    [Test]
    public async Task Create_Secret_Invalid_ApiResource_Fail()
    {
        var newSecret = ApiResourceSecretControllerExtensions.GetDefaultApiResourceSecretFor(0);

        SetControllerContext(_secretController, Admin);
        var response = await _secretController.CreatePropertyAsync(newSecret);
        Assert.That(response.Result, Is.TypeOf<BadRequestObjectResult>());
    }

    [Test]
    public void Create_Secret_Missing_ApiResource_Fail()
    {
        var newSecret = ApiResourceSecretControllerExtensions.GetDefaultApiResourceSecretFor(999);

        Assert.ThrowsAsync<EntityNotFoundException>(() => _secretController.Call_CreateSecretAsync(newSecret, Admin));
    }

    [Test]
    public async Task Created_Secret_Visible_In_ApiResource()
    {
        var createdApiResource = await _apiResourceController.Call_CreateApiResourceAsync(ApiResourceControllerExtensions.GetDefaultApiResource(1), Admin);
        var newSecret = ApiResourceSecretControllerExtensions.GetDefaultApiResourceSecretFor(createdApiResource.Id);
        _ = await _secretController.Call_CreateSecretAsync(newSecret, Admin);

        var retrievedApiResource = await _apiResourceController.Call_GetApiResourceAsync(createdApiResource.Id, Admin);

        Assert.That(retrievedApiResource.Secrets, Has.Count.EqualTo(1));
        var retrievedSecret = retrievedApiResource.Secrets[0];
        using (Assert.EnterMultipleScope())
        {
            Assert.That(retrievedSecret.Id, Is.Not.Zero);
            Assert.That(retrievedSecret.ApiResourceId, Is.EqualTo(createdApiResource.Id));
            Assert.That(retrievedSecret.Description, Is.EqualTo(newSecret.Description));
            Assert.That(retrievedSecret.Expiration, Is.Not.Null);
            Assert.That(retrievedSecret.Expiration, Is.GreaterThan(DateTime.UtcNow.AddYears(1)));
        }
    }

    [Test]
    public async Task Created_Secret_Matches_Saved_Hash()
    {
        var createdApiResource = await _apiResourceController.Call_CreateApiResourceAsync(ApiResourceControllerExtensions.GetDefaultApiResource(1), Admin);
        var newSecret = ApiResourceSecretControllerExtensions.GetDefaultApiResourceSecretFor(createdApiResource.Id);
        var createdSecret = await _secretController.Call_CreateSecretAsync(newSecret, Admin);

        var retrievedSecret = await _apiResourceSecretStorage.GetByIdAsync(createdSecret.Id);

        using (Assert.EnterMultipleScope())
        {
            Assert.That(retrievedSecret.Value, Is.EqualTo(createdSecret.Value.Sha256()));
        }
    }

    [Test]
    public async Task CreateSecret_WithSameDescription_Fails()
    {
        var createdApiResource = await _apiResourceController.Call_CreateApiResourceAsync(ApiResourceControllerExtensions.GetDefaultApiResource(1), Admin);
        var newSecret = ApiResourceSecretControllerExtensions.GetDefaultApiResourceSecretFor(createdApiResource.Id);
        _ = await _secretController.Call_CreateSecretAsync(newSecret, Admin);

        Assert.ThrowsAsync<EntityAlreadyExistsException>(() => _secretController.Call_CreateSecretAsync(newSecret, Admin));
    }

    [Test]
    public async Task CreateSecret_InvalidatesApiResourceCache()
    {
        // Arrange
        var createdApiResource = await _apiResourceController.Call_CreateApiResourceAsync(ApiResourceControllerExtensions.GetDefaultApiResource(1), Admin);
        var newSecret = ApiResourceSecretControllerExtensions.GetDefaultApiResourceSecretFor(createdApiResource.Id);

        // Act
        await _secretController.Call_CreateSecretAsync(newSecret, Admin);

        // Assert
        await _apiCache.Received(1).RemoveAsync(createdApiResource.Name);
    }

    [Test]
    public async Task DeleteSecret_InvalidatesApiResourceCache()
    {
        // Arrange
        var createdApiResource = await _apiResourceController.Call_CreateApiResourceAsync(ApiResourceControllerExtensions.GetDefaultApiResource(1), Admin);
        var newSecret = ApiResourceSecretControllerExtensions.GetDefaultApiResourceSecretFor(createdApiResource.Id);
        var createdSecret = await _secretController.Call_CreateSecretAsync(newSecret, Admin);
        _apiCache.ClearReceivedCalls();

        // Act
        await _secretController.Call_DeleteSecretAsync(createdSecret.Id, Admin);

        // Assert
        await _apiCache.Received(1).RemoveAsync(createdApiResource.Name);
    }
}
