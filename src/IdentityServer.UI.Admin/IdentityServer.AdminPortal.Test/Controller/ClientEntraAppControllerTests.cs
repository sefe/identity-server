using Microsoft.AspNetCore.Mvc;
using Microsoft.Extensions.DependencyInjection;
using NSubstitute;
using IdentityServer.Abstraction.Contracts.MicrosoftGraph;
using IdentityServer.Abstraction.Entities.EntraEntities;
using IdentityServer.Abstraction.Exceptions;
using IdentityServer.AdminPortal.Server.Controllers;
using IdentityServer.AdminPortal.Test.Extensions;
using IdentityServer.Tests.Common;

namespace IdentityServer.AdminPortal.Test.Controller;

[TestFixture]
public class ClientEntraAppControllerTests : ControllerTestBase
{
    private ClientPropertyEntraAppController _clientEntraAppController;
    private ClientController _clientController;

    private readonly IEntraApplicationService _entraApplicationService = Substitute.For<IEntraApplicationService>();

    private const int _environmentId = 1;
    private const string _entraAppName = "Test App Name";

    [SetUp]
    public async Task Setup()
    {
        var provider = IoC.GetProvider(sc =>
        {
            sc.AddScoped<ClientPropertyEntraAppController>();
            sc.AddScoped<ClientController>();

            sc.AddSingleton(_entraApplicationService);

            sc.ReplaceWithInstance(EverythingIsAllowed);
        });

        await Setup(provider);

        _clientEntraAppController = provider.GetRequiredService<ClientPropertyEntraAppController>();
        _clientController = provider.GetRequiredService<ClientController>();
    }

    [Test]
    [TestCase("12345678-1234-1234-1234-123456789012")]
    [TestCase("abcdef00-abcd-abcd-abcd-abcdef000000")]
    public async Task AddClientEntraAppAsync_ValidAppId_Succeeds(string entraAppId)
    {
        // Arrange
        var entraApp = new Application { AppId = entraAppId, Id = "1", DisplayName = _entraAppName };
        _entraApplicationService.GetByIdAsync(entraAppId).Returns(entraApp);
        var client = await _clientController.Call_CreateClientAsync(ClientControllerExtensions.GetDefaultClient(_environmentId), Contributor);

        // Act
        var addedEntraApp = await _clientEntraAppController.Call_AddClientEntraAppAsync(client.Id, entraAppId, Contributor);
        var updatedClient = await _clientController.Call_GetClientAsync(client.Id, Contributor);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            ClientEntraAppControllerExtensions.AssertClientEntraAppIsValid(addedEntraApp, client.Id, entraAppId);
            ClientEntraAppControllerExtensions.AssertClientHasEntraApp(updatedClient, entraAppId);
            Assert.That(updatedClient.EntraApps[0].AppName, Is.EqualTo(_entraAppName));
        }
    }

    [Test]
    public async Task AddClientEntraAppAsync_WithOnlyCaseDifferences_Fails()
    {
        // Arrange
        const string originalEntraAppId = "12345678-abcd-1234-1234-123456789012";
        const string caseDifferentEntraAppId = "12345678-ABCD-1234-1234-123456789012";
        var entraApp = new Application { AppId = originalEntraAppId, Id = "1", DisplayName = _entraAppName };
        _entraApplicationService.GetByIdAsync(Arg.Any<string>()).Returns(entraApp);
        var client = await _clientController.Call_CreateClientAsync(ClientControllerExtensions.GetDefaultClient(_environmentId), Contributor);
        await _clientEntraAppController.Call_AddClientEntraAppAsync(client.Id, originalEntraAppId, Contributor);

        // Act & Assert
        Assert.ThrowsAsync<EntityAlreadyExistsException>(() => _clientEntraAppController.Call_AddClientEntraAppAsync(client.Id, caseDifferentEntraAppId, Contributor));
    }

    [Test]
    [TestCase("")]
    [TestCase("not-a-guid")]
    [TestCase("12345")]
    public async Task AddClientEntraAppAsync_InvalidAppId_Fails(string invalidAppId)
    {
        // Arrange
        _entraApplicationService.GetByIdAsync(Arg.Any<string>()).Returns((Application)null);
        var client = await _clientController.Call_CreateClientAsync(ClientControllerExtensions.GetDefaultClient(_environmentId), Contributor);
        var entraAppDto = new Abstraction.DTO.Clients.ClientPropertyEntraAppDtoCreate
        {
            ClientId = client.Id,
            AppId = invalidAppId
        };

        // Act
        SetControllerContext(_clientEntraAppController, Contributor);
        var response = await _clientEntraAppController.CreatePropertyAsync(entraAppDto);

        // Assert
        Assert.That(response.Result, Is.TypeOf<BadRequestObjectResult>());
    }

    [Test]
    public async Task AddClientEntraAppAsync_WithDuplicateAppId_Fails()
    {
        // Arrange
        const string appId = "12345678-1234-1234-1234-123456789012";
        var entraApp = new Application { AppId = appId, Id = "1", DisplayName = _entraAppName };
        _entraApplicationService.GetByIdAsync(Arg.Any<string>()).Returns(entraApp);
        var client = await _clientController.Call_CreateClientAsync(ClientControllerExtensions.GetDefaultClient(_environmentId), Contributor);

        // Act & Assert
        await _clientEntraAppController.Call_AddClientEntraAppAsync(client.Id, appId, Contributor);
        Assert.ThrowsAsync<EntityAlreadyExistsException>(() => _clientEntraAppController.Call_AddClientEntraAppAsync(client.Id, appId, Contributor));
    }

    [Test]
    public void AddClientEntraAppAsync_ToInvalidClient_Fails()
    {
        // Arrange
        const string appId = "12345678-1234-1234-1234-123456789012";
        var entraApp = new Application { AppId = appId, Id = "1", DisplayName = _entraAppName };
        _entraApplicationService.GetByIdAsync(Arg.Any<string>()).Returns(entraApp);
        var entraAppDto = new Abstraction.DTO.Clients.ClientPropertyEntraAppDtoCreate
        {
            ClientId = 999,
            AppId = appId
        };

        // Act & Assert
        SetControllerContext(_clientEntraAppController, Contributor);
        Assert.ThrowsAsync<EntityNotFoundException>(() => _clientEntraAppController.CreatePropertyAsync(entraAppDto));
    }

    [Test]
    public async Task AddClientEntraAppAsync_MultipleAppsToSameClient_Succeeds()
    {
        // Arrange
        const string appId1 = "12345678-1234-1234-1234-123456789012";
        const string appId2 = "87654321-4321-4321-4321-210987654321";
        _entraApplicationService.GetByIdAsync(Arg.Any<string>()).Returns(ci => new Application { AppId = ci.Arg<string>(), Id = ci.Arg<string>(), DisplayName = ci.Arg<string>() });
        var client = await _clientController.Call_CreateClientAsync(ClientControllerExtensions.GetDefaultClient(_environmentId), Contributor);

        // Act
        var addedEntraApp1 = await _clientEntraAppController.Call_AddClientEntraAppAsync(client.Id, appId1, Contributor);
        var addedEntraApp2 = await _clientEntraAppController.Call_AddClientEntraAppAsync(client.Id, appId2, Contributor);
        var updatedClient = await _clientController.Call_GetClientAsync(client.Id, Contributor);

        // Assert
        Assert.That(updatedClient.EntraApps, Has.Count.EqualTo(2));
        ClientEntraAppControllerExtensions.AssertClientEntraAppIsValid(addedEntraApp1, client.Id, appId1);
        ClientEntraAppControllerExtensions.AssertClientEntraAppIsValid(addedEntraApp2, client.Id, appId2);
        ClientEntraAppControllerExtensions.AssertClientHasEntraApp(updatedClient, appId1);
        ClientEntraAppControllerExtensions.AssertClientHasEntraApp(updatedClient, appId2);
    }

    [Test]
    public async Task DeleteClientEntraAppAsync_WithExistingId_Succeeds()
    {
        // Arrange
        const string appId = "12345678-1234-1234-1234-123456789012";
        _entraApplicationService.GetByIdAsync(Arg.Any<string>()).Returns(ci => new Application { AppId = ci.Arg<string>(), Id = ci.Arg<string>(), DisplayName = ci.Arg<string>() });
        var client = await _clientController.Call_CreateClientAsync(ClientControllerExtensions.GetDefaultClient(_environmentId), Contributor);
        var addedEntraApp = await _clientEntraAppController.Call_AddClientEntraAppAsync(client.Id, appId, Contributor);

        // Act
        var deletedId = await _clientEntraAppController.Call_DeleteClientEntraAppAsync(addedEntraApp.Id, Contributor);

        // Assert
        var updatedClient = await _clientController.Call_GetClientAsync(client.Id, Contributor);
        Assert.That(deletedId, Is.EqualTo(addedEntraApp.Id));
        ClientEntraAppControllerExtensions.AssertClientDoesNotHaveEntraApp(updatedClient, appId);
    }

    [Test]
    public async Task DeleteClientEntraAppAsync_WithInvalidId_ReturnsNotFound()
    {
        // Arrange
        const int invalidId = 999;

        // Act & Assert
        SetControllerContext(_clientEntraAppController, Contributor);
        var response = await _clientEntraAppController.DeletePropertyByIdAsync(invalidId);
        Assert.That(response.Result, Is.InstanceOf<NotFoundResult>());
    }

    [Test]
    public async Task DeleteClientEntraAppAsync_OneOfMultipleApps_RemovesOnlySpecifiedApp()
    {
        // Arrange
        const string appId1 = "12345678-1234-1234-1234-123456789012";
        const string appId2 = "87654321-4321-4321-4321-210987654321";
        _entraApplicationService.GetByIdAsync(Arg.Any<string>()).Returns(ci => new Application { AppId = ci.Arg<string>(), Id = ci.Arg<string>(), DisplayName = ci.Arg<string>() });
        var client = await _clientController.Call_CreateClientAsync(ClientControllerExtensions.GetDefaultClient(_environmentId), Contributor);
        var addedEntraApp1 = await _clientEntraAppController.Call_AddClientEntraAppAsync(client.Id, appId1, Contributor);
        await _clientEntraAppController.Call_AddClientEntraAppAsync(client.Id, appId2, Contributor);

        // Act
        var deletedId = await _clientEntraAppController.Call_DeleteClientEntraAppAsync(addedEntraApp1.Id, Contributor);

        // Assert
        var updatedClient = await _clientController.Call_GetClientAsync(client.Id, Contributor);
        Assert.That(deletedId, Is.EqualTo(addedEntraApp1.Id));
        ClientEntraAppControllerExtensions.AssertClientDoesNotHaveEntraApp(updatedClient, appId1);
        ClientEntraAppControllerExtensions.AssertClientHasEntraApp(updatedClient, appId2);
        Assert.That(updatedClient.EntraApps, Has.Count.EqualTo(1));
    }
}
