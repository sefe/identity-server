using Microsoft.AspNetCore.Mvc;
using Microsoft.Extensions.DependencyInjection;
using IdentityServer.Abstraction.Contracts;
using IdentityServer.Abstraction.DTO.Clients;
using IdentityServer.Controllers;
using IdentityServer.Data.DuendeEntityExtensions;
using IdentityServer.Test.Extensions;
using IdentityServer.Tests.Common.Builders;

namespace IdentityServer.Test.Controller;

public class ClientsControllerTests : ControllerTestBase
{
    private ClientsController _clientController;
    private MockStorage<ClientExt> _clientStorageMock;

    [SetUp]
    public void Setup()
    {
        _clientStorageMock = new MockStorage<ClientExt>(c => c.Id);

        var provider = IoC.GetProvider(sc =>
        {
            sc.AddScoped<ClientsController>();
            sc.ReplaceWithInstance<IStorage<ClientExt>>(_clientStorageMock);
        });

        _clientController = provider.GetRequiredService<ClientsController>();
    }

    [Test]
    public async Task SearchClientsAsync_ReturnsOk_WithValidRequest_AndResults()
    {
        // Arrange
        var request = new ClientDtoSearchRequest
        {
            SearchTerm = "test",
            Page = 1,
            PageSize = 10
        };

        await _clientStorageMock.AddAsync(new ClientExtBuilder("test1", "Test Client 1").Build());
        await _clientStorageMock.AddAsync(new ClientExtBuilder("test2", "Test Client 2").Build());

        // Act
        var searchResult = await _clientController.Call_SearchClientsAsync(request);

        using (Assert.EnterMultipleScope())
        {
            // Assert
            Assert.That(searchResult.TotalCount, Is.EqualTo(_clientStorageMock.Items.Count));
            Assert.That(searchResult.Page, Has.Count.EqualTo(_clientStorageMock.Items.Count));
            Assert.That(searchResult.PageNumber, Is.EqualTo(request.Page));
            Assert.That(searchResult.PageSize, Is.EqualTo(request.PageSize));
        }
        using (Assert.EnterMultipleScope())
        {
            Assert.That(searchResult.Page[0].ClientId, Is.EqualTo(_clientStorageMock.Items[0].ClientId));
            Assert.That(searchResult.Page[1].ClientId, Is.EqualTo(_clientStorageMock.Items[1].ClientId));
        }
    }

    [Test]
    public async Task SearchClientsAsync_ReturnsOk_WithValidRequest_AndNoResults()
    {
        // Arrange
        var request = new ClientDtoSearchRequest
        {
            SearchTerm = "notfound",
            Page = 1,
            PageSize = 10
        };

        await _clientStorageMock.AddAsync(new ClientExtBuilder("test1", "Test Client 1").Build());
        await _clientStorageMock.AddAsync(new ClientExtBuilder("test2", "Test Client 2").Build());

        // Act
        var searchResult = await _clientController.Call_SearchClientsAsync(request);

        using (Assert.EnterMultipleScope())
        {
            // Assert
            Assert.That(searchResult.TotalCount, Is.Zero);
            Assert.That(searchResult.Page, Is.Empty);
            Assert.That(searchResult.PageNumber, Is.EqualTo(request.Page));
            Assert.That(searchResult.PageSize, Is.EqualTo(request.PageSize));
        }
    }

    [Test]
    public async Task SearchClientsAsync_ReturnsBadRequest_WhenModelStateIsInvalid()
    {
        // Arrange
        var request = new ClientDtoSearchRequest
        {
            SearchTerm = "ab", // too short, should trigger validation error
            Page = 1,
            PageSize = 10
        };

        _clientController.ModelState.AddModelError("SearchTerm", "Search Term must be at least 3 symbols long.");

        // Act
        var result = await _clientController.SearchClientsAsync(request);

        // Assert
        Assert.That(result.Result, Is.InstanceOf<BadRequestObjectResult>());
        var badRequest = result.Result as BadRequestObjectResult;
        Assert.That(badRequest, Is.Not.Null);
        Assert.That(badRequest!.Value, Is.InstanceOf<SerializableError>());
        var errors = badRequest.Value as SerializableError;
        using (Assert.EnterMultipleScope())
        {
            Assert.That(errors, Contains.Key("SearchTerm"));
            Assert.That(((string[])errors["SearchTerm"])[0], Is.EqualTo("Search Term must be at least 3 symbols long."));
        }
    }

    [Test]
    public async Task GetClientByIdAsync_ReturnsOk_WhenClientExists()
    {
        // Arrange
        var clientId = "test-client";
        string clientName = "Test Client";
        await _clientStorageMock.AddAsync(new ClientExtBuilder(clientId, clientName).Build());

        // Act
        var result = await _clientController.Call_GetClientByClientIdAsync(clientId);

        // Assert
        Assert.That(result, Is.Not.Null);
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result!.ClientId, Is.EqualTo(clientId));
            Assert.That(result.ClientName, Is.EqualTo(clientName));
        }
    }

    [Test]
    public async Task GetClientByIdAsync_ReturnsNotFound_WhenClientDoesNotExist()
    {
        // Arrange
        var clientId = "missing-client";

        // No clients in storage

        // Act
        var result = await _clientController.GetClientByClientIdAsync(clientId);

        // Assert
        Assert.That(result.Result, Is.InstanceOf<NotFoundObjectResult>());
        var notFound = result.Result as NotFoundObjectResult;
        Assert.That(notFound, Is.Not.Null);
        Assert.That(notFound!.Value, Is.EqualTo($"Client with ID '{clientId}' not found."));
    }

    [Test]
    public async Task GetClientByIdAsync_ReturnsBadRequest_WhenClientIdIsNullOrEmpty()
    {
        // Arrange
        var invalidClientIds = new[] { null, "" };

        foreach (var clientId in invalidClientIds)
        {
            // Act
            var result = await _clientController.GetClientByClientIdAsync(clientId);

            // Assert
            Assert.That(result.Result, Is.InstanceOf<BadRequestObjectResult>());
            var badRequest = result.Result as BadRequestObjectResult;
            Assert.That(badRequest, Is.Not.Null);
            Assert.That(badRequest!.Value, Is.EqualTo("Invalid client ID."));
        }
    }
}
