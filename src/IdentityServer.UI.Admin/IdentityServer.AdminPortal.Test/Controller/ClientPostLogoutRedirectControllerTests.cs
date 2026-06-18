using Microsoft.AspNetCore.Mvc;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging;
using NSubstitute;
using IdentityServer.Abstraction.Contracts;
using IdentityServer.Abstraction.DTO.Clients;
using IdentityServer.Abstraction.Exceptions;
using IdentityServer.AdminPortal.Server.Controllers;
using IdentityServer.AdminPortal.Test.Extensions;
using IdentityServer.Data.Repositories.DtoRepositories.Client;
using IdentityServer.Tests.Common;
using DataEntities = Duende.IdentityServer.EntityFramework.Entities;

namespace IdentityServer.AdminPortal.Test.Controller;

public class ClientPostLogoutRedirectControllerTests : ControllerTestBase
{
    private ClientPropertyPostLogoutRedirectController _clientPostLogoutRedirectController;
    private ClientController _clientController;
    private MockLogger<ClientPropertyPostLogoutRedirectUriDtoRepository> _mockLogger;
    private ICache<DataEntities.Client> _clientCache;

    [SetUp]
    public async Task Setup()
    {
        _mockLogger = new MockLogger<ClientPropertyPostLogoutRedirectUriDtoRepository>();
        _clientCache = Substitute.For<ICache<DataEntities.Client>>();

        var provider = IoC.GetProvider(sc =>
        {
            sc.AddScoped<ClientPropertyPostLogoutRedirectController>();
            sc.AddScoped<ClientController>();
            sc.ReplaceWithInstance(EverythingIsAllowed);
            sc.ReplaceWithInstance(_clientCache);
            sc.AddSingleton<ILogger<ClientPropertyPostLogoutRedirectUriDtoRepository>>(_mockLogger);
        });

        await Setup(provider);

        _clientPostLogoutRedirectController = provider.GetRequiredService<ClientPropertyPostLogoutRedirectController>();
        _clientController = provider.GetRequiredService<ClientController>();
    }

    [Test]
    [TestCase("https://secure.com/logout")]
    [TestCase("http://insecure.com/signout")]
    public async Task AddClientPostLogoutRedirectAsync_ValidPostLogoutRedirectUri_Succeeds(string postLogoutRedirectUri)
    {
        // Arrange
        var client = await _clientController.Call_CreateClientAsync(ClientControllerExtensions.GetDefaultClient(1), Contributor);

        // Act
        var addedPostLogoutRedirect = await _clientPostLogoutRedirectController.Call_AddClientPostLogoutRedirectAsync(client.Id, postLogoutRedirectUri, Contributor);
        var updatedClient = await _clientController.Call_GetClientAsync(client.Id, Contributor);

        // Assert
        ClientPostLogoutRedirectControllerExtensions.AssertClientPostLogoutRedirectIsValid(addedPostLogoutRedirect, client.Id, postLogoutRedirectUri);
        ClientPostLogoutRedirectControllerExtensions.AssertClientHasPostLogoutRedirectUri(updatedClient, postLogoutRedirectUri);
    }

    [Test]
    public async Task AddClientPostLogoutRedirectAsync_WithOnlyCaseDifferences_Fails()
    {
        // Arrange
        var originalUri = "https://secure.com/logout";
        var caseDifferentUri = "Https://Secure.com/Logout";
        var client = await _clientController.Call_CreateClientAsync(ClientControllerExtensions.GetDefaultClient(1), Contributor);
        await _clientPostLogoutRedirectController.Call_AddClientPostLogoutRedirectAsync(client.Id, originalUri, Contributor);

        // Act & Assert
        Assert.ThrowsAsync<EntityAlreadyExistsException>(() => _clientPostLogoutRedirectController.Call_AddClientPostLogoutRedirectAsync(client.Id, caseDifferentUri, Contributor));
    }

    [Test]
    public async Task AddClientPostLogoutRedirectAsync_InvalidPostLogoutRedirectUri_Fails()
    {
        // Arrange
        var invalidPostLogoutRedirectUri = "invalid-url";
        var client = await _clientController.Call_CreateClientAsync(ClientControllerExtensions.GetDefaultClient(1), Contributor);
        SetControllerContext(_clientPostLogoutRedirectController, Contributor);
        var postLogoutRedirectDto = new ClientPropertyPostLogoutRedirectUriDtoCreate
        {
            ClientId = client.Id,
            PostLogoutRedirectUri = invalidPostLogoutRedirectUri
        };

        // Act
        var response = await _clientPostLogoutRedirectController.CreatePropertyAsync(postLogoutRedirectDto);

        // Assert
        Assert.That(response.Result, Is.TypeOf<BadRequestObjectResult>());
    }

    [Test]
    [TestCase("http://test.sefe.eu/logout")]
    [TestCase("http://127.0.0.2/signout")]
    public async Task AddClientPostLogoutRedirectAsync_WithInsecurePostLogoutRedirectUri_LogsWarning(string insecurePostLogoutRedirectUri)
    {
        // Arrange
        var client = await _clientController.Call_CreateClientAsync(ClientControllerExtensions.GetDefaultClient(1), Contributor);
        var expectedWarningMessage = $"Insecure HTTP Post-Logout Redirect URI is added to {client.ClientId}: {insecurePostLogoutRedirectUri}";

        // Act
        var response = await _clientPostLogoutRedirectController.Call_AddClientPostLogoutRedirectAsync(client.Id, insecurePostLogoutRedirectUri, Contributor);
        ClientPostLogoutRedirectControllerExtensions.AssertClientPostLogoutRedirectIsValid(response, client.Id, insecurePostLogoutRedirectUri);

        // Assert
        Assert.That(_mockLogger.CapturedWarnings, Has.Count.EqualTo(1));
        Assert.That(_mockLogger.CapturedWarnings[0], Does.Contain(expectedWarningMessage), "Expected warning message was not logged.");
    }

    [Test]
    [TestCase("http://localhost/logout")]
    [TestCase("http://127.0.0.1/signout")]
    public async Task AddClientPostLogoutRedirectAsync_WithInsecureLoopbackPostLogoutRedirectUri_DoesntLogWarning(string insecurePostLogoutRedirectUri)
    {
        // Arrange
        var client = await _clientController.Call_CreateClientAsync(ClientControllerExtensions.GetDefaultClient(1), Contributor);

        // Act
        var response = await _clientPostLogoutRedirectController.Call_AddClientPostLogoutRedirectAsync(client.Id, insecurePostLogoutRedirectUri, Contributor);

        // Assert
        ClientPostLogoutRedirectControllerExtensions.AssertClientPostLogoutRedirectIsValid(response, client.Id, insecurePostLogoutRedirectUri);
        Assert.That(_mockLogger.CapturedWarnings, Has.Count.EqualTo(0));
    }

    [Test]
    public async Task AddClientPostLogoutRedirectAsync_InvalidatesCache()
    {
        // Arrange
        var postLogoutRedirectUri = "https://example.com/logout";
        var client = await _clientController.Call_CreateClientAsync(ClientControllerExtensions.GetDefaultClient(1), Contributor);

        // Act
        await _clientPostLogoutRedirectController.Call_AddClientPostLogoutRedirectAsync(client.Id, postLogoutRedirectUri, Contributor);

        // Assert
        await _clientCache.Received(1).RemoveAsync(client.ClientId);
    }

    [Test]
    public async Task DeleteClientPostLogoutRedirectAsync_WithExistingId_Succeeds()
    {
        // Arrange
        var postLogoutRedirectUri = "https://example.com/logout";
        var client = await _clientController.Call_CreateClientAsync(ClientControllerExtensions.GetDefaultClient(1), Contributor);
        var addedPostLogoutRedirect = await _clientPostLogoutRedirectController.Call_AddClientPostLogoutRedirectAsync(client.Id, postLogoutRedirectUri, Contributor);

        // Act
        var deletedId = await _clientPostLogoutRedirectController.Call_DeleteClientPostLogoutRedirectAsync(addedPostLogoutRedirect.Id, Contributor);

        // Assert
        var updatedClient = await _clientController.Call_GetClientAsync(client.Id, Contributor);
        Assert.That(deletedId, Is.EqualTo(addedPostLogoutRedirect.Id));
        ClientPostLogoutRedirectControllerExtensions.AssertClientDoesNotHavePostLogoutRedirectUri(updatedClient, postLogoutRedirectUri);
    }

    [Test]
    public async Task DeleteClientPostLogoutRedirectAsync_WithInvalidId_ReturnsNotFound()
    {
        // Arrange
        SetControllerContext(_clientPostLogoutRedirectController, Contributor);

        // Act
        var response = await _clientPostLogoutRedirectController.DeletePropertyByIdAsync(999);

        // Assert
        Assert.That(response.Result, Is.TypeOf<NotFoundResult>());
    }

    [Test]
    public async Task DeleteClientPostLogoutRedirectAsync_InvalidatesCache()
    {
        // Arrange
        var postLogoutRedirectUri = "https://example.com/logout";
        var client = await _clientController.Call_CreateClientAsync(ClientControllerExtensions.GetDefaultClient(1), Contributor);
        var addedPostLogoutRedirect = await _clientPostLogoutRedirectController.Call_AddClientPostLogoutRedirectAsync(client.Id, postLogoutRedirectUri, Contributor);

        // Reset the mock to clear previous calls
        _clientCache.ClearReceivedCalls();

        // Act
        await _clientPostLogoutRedirectController.Call_DeleteClientPostLogoutRedirectAsync(addedPostLogoutRedirect.Id, Contributor);

        // Assert
        await _clientCache.Received(1).RemoveAsync(client.ClientId);
    }
}
