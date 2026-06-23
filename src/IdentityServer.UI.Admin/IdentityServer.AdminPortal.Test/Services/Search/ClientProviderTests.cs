// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

using System.Net;
using NSubstitute;
using IdentityServer.Abstraction.DTO.Clients;
using IdentityServer.AdminPortal.Web.Models;
using IdentityServer.AdminPortal.Web.Services;
using IdentityServer.AdminPortal.Web.Services.Search;
using IdentityServer.Tests.Common;

namespace IdentityServer.AdminPortal.Test.Services.Search;

[TestFixture]
public class ClientProviderTests
{
    private IHttpClientFactory _mockHttpClientFactory;

    [SetUp]
    public void SetUp()
    {
        _mockHttpClientFactory = Substitute.For<IHttpClientFactory>();
    }

    private ClientProvider CreateClientProviderWithFixedResponse()
    {
        var fixedClients = new List<ClientShortDtoRead>
        {
            new() { ClientId = "client1", ClientName = "Test Client 1" },
            new() { ClientId = "client2", ClientName = "Test Client 2" }
        };
        var responseData = new DataEnvelope<ClientShortDtoRead> { CurrentPageData = fixedClients };
        var httpClient = new HttpClient(new MockHttpMessageHandler(HttpStatusCode.OK, responseData))
        {
            BaseAddress = new Uri("http://localhost:5300")
        };
        _mockHttpClientFactory.CreateClient(AdminApiService.HttpClientName).Returns(httpClient);

        var adminApiService = new AdminApiService(_mockHttpClientFactory);
        return new ClientProvider(adminApiService);
    }

    [Test]
    public async Task SearchAsync_WithValidInputAndNoSkipToken_DefaultsToPage1()
    {
        // Arrange
        var clientProvider = CreateClientProviderWithFixedResponse();

        // Act
        var result = await clientProvider.SearchAsync("test", null);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result.Page, Has.Count.EqualTo(2));
            Assert.That(result.SkipToken, Is.EqualTo("2"));
            Assert.That(result.ErrorMessage, Is.Null);
        }
    }

    [Test]
    public async Task SearchAsync_WithValidSkipToken_UsesCorrectPageNumber()
    {
        // Arrange
        var clientProvider = CreateClientProviderWithFixedResponse();

        // Act
        var result = await clientProvider.SearchAsync("test", "3");

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result.Page, Has.Count.EqualTo(2));
            Assert.That(result.SkipToken, Is.EqualTo("4"));
            Assert.That(result.ErrorMessage, Is.Null);
        }
    }

    [Test]
    public async Task SearchAsync_WithInvalidSkipToken_DefaultsToPage1()
    {
        // Arrange
        var clientProvider = CreateClientProviderWithFixedResponse();

        // Act
        var result = await clientProvider.SearchAsync("test", "invalid");

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result.Page, Has.Count.EqualTo(2));
            Assert.That(result.SkipToken, Is.EqualTo("2"));
            Assert.That(result.ErrorMessage, Is.Null);
        }
    }

    [Test]
    public async Task SearchAsync_WithEmptySkipToken_DefaultsToPage1()
    {
        // Arrange
        var clientProvider = CreateClientProviderWithFixedResponse();

        // Act
        var result = await clientProvider.SearchAsync("test", string.Empty);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result.Page, Has.Count.EqualTo(2));
            Assert.That(result.SkipToken, Is.EqualTo("2"));
            Assert.That(result.ErrorMessage, Is.Null);
        }
    }

    [Test]
    public async Task SearchAsync_WithErrorFromAdminApi_ReturnsErrorMessage()
    {
        // Arrange
        var httpClient = new HttpClient(new MockHttpMessageHandler(HttpStatusCode.OK, null)); // fails to work without a Base Url configured
        _mockHttpClientFactory.CreateClient(AdminApiService.HttpClientName).Returns(httpClient);

        var adminApiService = new AdminApiService(_mockHttpClientFactory);
        var clientProvider = new ClientProvider(adminApiService);

        // Act
        var result = await clientProvider.SearchAsync("test", null);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result.Page, Is.Null);
            Assert.That(result.SkipToken, Is.EqualTo("2"));
            Assert.That(result.ErrorMessage, Is.Not.Null);
        }
    }

    [Test]
    public async Task SearchAsync_WhenNoResultsFound_ReturnsEmptyList()
    {
        // Arrange
        var responseData = new DataEnvelope<ClientShortDtoRead> { CurrentPageData = new List<ClientShortDtoRead>() };
        var httpClient = new HttpClient(new MockHttpMessageHandler(HttpStatusCode.OK, responseData))
        {
            BaseAddress = new Uri("http://localhost:5300")
        };
        _mockHttpClientFactory.CreateClient(AdminApiService.HttpClientName).Returns(httpClient);

        var adminApiService = new AdminApiService(_mockHttpClientFactory);
        var clientProvider = new ClientProvider(adminApiService);

        // Act
        var result = await clientProvider.SearchAsync("nonexistent", null);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result.Page, Is.Empty);
            Assert.That(result.SkipToken, Is.EqualTo("2"));
            Assert.That(result.ErrorMessage, Is.Null);
        }
    }
}
