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

public class ClientRedirectControllerTests : ControllerTestBase
{
    private ClientPropertyRedirectController _clientRedirectController;
    private ClientController _clientController;
    private MockLogger<ClientPropertyRedirectUriDtoRepository> _mockLogger;
    private ICache<DataEntities.Client> _clientCache;

    [SetUp]
    public async Task Setup()
    {
        _mockLogger = new MockLogger<ClientPropertyRedirectUriDtoRepository>();
        _clientCache = Substitute.For<ICache<DataEntities.Client>>();

        var provider = IoC.GetProvider(sc =>
        {
            sc.AddScoped<ClientPropertyRedirectController>();
            sc.AddScoped<ClientController>();
            sc.ReplaceWithInstance(EverythingIsAllowed);
            sc.ReplaceWithInstance(_clientCache);
            sc.AddSingleton<ILogger<ClientPropertyRedirectUriDtoRepository>>(_mockLogger);
        });

        await Setup(provider);

        _clientRedirectController = provider.GetRequiredService<ClientPropertyRedirectController>();
        _clientController = provider.GetRequiredService<ClientController>();
    }

    [Test]
    [TestCase("https://secure.com/callback")]
    [TestCase("http://insecure.com/redirect")]
    public async Task AddClientRedirectAsync_ValidRedirectUri_Succeeds(string redirectUri)
    {
        // Arrange
        var client = await _clientController.Call_CreateClientAsync(ClientControllerExtensions.GetDefaultClient(1), Contributor);

        // Act
        var addedRedirect = await _clientRedirectController.Call_AddClientRedirectAsync(client.Id, redirectUri, Contributor);
        var updatedClient = await _clientController.Call_GetClientAsync(client.Id, Contributor);

        // Assert
        ClientRedirectControllerExtensions.AssertClientRedirectIsValid(addedRedirect, client.Id, redirectUri);
        ClientRedirectControllerExtensions.AssertClientHasRedirectUri(updatedClient, redirectUri);
    }

    [Test]
    public async Task AddClientRedirectAsync_WithOnlyCaseDifferences_Fails()
    {
        // Arrange
        var originalUri = "https://secure.com/callback";
        var caseDifferentUri = "Https://Secure.com/Callback";
        var client = await _clientController.Call_CreateClientAsync(ClientControllerExtensions.GetDefaultClient(1), Contributor);
        await _clientRedirectController.Call_AddClientRedirectAsync(client.Id, originalUri, Contributor);

        // Act & Assert
        Assert.ThrowsAsync<EntityAlreadyExistsException>(() => _clientRedirectController.Call_AddClientRedirectAsync(client.Id, caseDifferentUri, Contributor));
    }

    [Test]
    public async Task AddClientRedirectAsync_InvalidRedirectUri_Fails()
    {
        // Arrange
        var invalidRedirectUri = "invalid-url";
        var client = await _clientController.Call_CreateClientAsync(ClientControllerExtensions.GetDefaultClient(1), Contributor);
        SetControllerContext(_clientRedirectController, Contributor);
        var redirectDto = new ClientPropertyRedirectUriDtoCreate
        {
            ClientId = client.Id,
            RedirectUri = invalidRedirectUri
        };

        // Act
        var response = await _clientRedirectController.CreatePropertyAsync(redirectDto);

        // Assert
        Assert.That(response.Result, Is.TypeOf<BadRequestObjectResult>());
    }

    [Test]
    [TestCase("http://test.sefe.eu/123")]
    [TestCase("http://127.0.0.2/123")]
    public async Task AddClientRedirectAsync_WithInsecureRedirectUri_LogsWarning(string insecureRedirectUri)
    {
        // Arrange
        var client = await _clientController.Call_CreateClientAsync(ClientControllerExtensions.GetDefaultClient(1), Contributor);
        var expectedWarningMessage = $"Insecure HTTP Redirect URI is added to {client.ClientId}: {insecureRedirectUri}";

        // Act
        var response = await _clientRedirectController.Call_AddClientRedirectAsync(client.Id, insecureRedirectUri, Contributor);
        ClientRedirectControllerExtensions.AssertClientRedirectIsValid(response, client.Id, insecureRedirectUri);

        // Assert
        Assert.That(_mockLogger.CapturedWarnings, Has.Count.EqualTo(1));
        Assert.That(_mockLogger.CapturedWarnings[0], Does.Contain(expectedWarningMessage), "Expected warning message was not logged.");
    }

    [Test]
    [TestCase("http://localhost/123")]
    [TestCase("http://127.0.0.1/123")]
    public async Task AddClientRedirectAsync_WithInsecureLoopbackRedirectUri_DoesntLogWarning(string insecureRedirectUri)
    {
        // Arrange
        var client = await _clientController.Call_CreateClientAsync(ClientControllerExtensions.GetDefaultClient(1), Contributor);

        // Act
        var response = await _clientRedirectController.Call_AddClientRedirectAsync(client.Id, insecureRedirectUri, Contributor);

        // Assert
        ClientRedirectControllerExtensions.AssertClientRedirectIsValid(response, client.Id, insecureRedirectUri);
        Assert.That(_mockLogger.CapturedWarnings, Has.Count.EqualTo(0));
    }

    [Test]
    public async Task AddClientRedirectAsync_InvalidatesCache()
    {
        // Arrange
        var redirectUri = "https://example.com/callback";
        var client = await _clientController.Call_CreateClientAsync(ClientControllerExtensions.GetDefaultClient(1), Contributor);

        // Act
        await _clientRedirectController.Call_AddClientRedirectAsync(client.Id, redirectUri, Contributor);

        // Assert
        await _clientCache.Received(1).RemoveAsync(client.ClientId);
    }

    [Test]
    public async Task DeleteClientRedirectAsync_WithExistingId_Succeeds()
    {
        // Arrange
        var redirectUri = "https://example.com/callback";
        var client = await _clientController.Call_CreateClientAsync(ClientControllerExtensions.GetDefaultClient(1), Contributor);
        var addedRedirect = await _clientRedirectController.Call_AddClientRedirectAsync(client.Id, redirectUri, Contributor);

        // Act
        var deletedId = await _clientRedirectController.Call_DeleteClientRedirectAsync(addedRedirect.Id, Contributor);

        // Assert
        var updatedClient = await _clientController.Call_GetClientAsync(client.Id, Contributor);
        Assert.That(deletedId, Is.EqualTo(addedRedirect.Id));
        ClientRedirectControllerExtensions.AssertClientDoesNotHaveRedirectUri(updatedClient, redirectUri);
    }

    [Test]
    public async Task DeleteClientRedirectAsync_WithInvalidId_ReturnsNotFound()
    {
        // Arrange
        SetControllerContext(_clientRedirectController, Contributor);

        // Act
        var response = await _clientRedirectController.DeletePropertyByIdAsync(999);

        // Assert
        Assert.That(response.Result, Is.TypeOf<NotFoundResult>());
    }

    [Test]
    public async Task DeleteClientRedirectAsync_InvalidatesCache()
    {
        // Arrange
        var redirectUri = "https://example.com/callback";
        var client = await _clientController.Call_CreateClientAsync(ClientControllerExtensions.GetDefaultClient(1), Contributor);
        var addedRedirect = await _clientRedirectController.Call_AddClientRedirectAsync(client.Id, redirectUri, Contributor);

        // Reset the mock to clear previous calls
        _clientCache.ClearReceivedCalls();

        // Act
        await _clientRedirectController.Call_DeleteClientRedirectAsync(addedRedirect.Id, Contributor);

        // Assert
        await _clientCache.Received(1).RemoveAsync(client.ClientId);
    }
}
