// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

using NSubstitute;
using System.Net;
using IdentityServer.Abstraction.Entities.EntraEntities;
using IdentityServer.AdminPortal.Web.Services;
using IdentityServer.AdminPortal.Web.Services.Search;
using IdentityServer.Tests.Common;

namespace IdentityServer.AdminPortal.Test.Services.Search;

[TestFixture]
public class EntraGroupSearchProviderTests
{
    private IHttpClientFactory _mockHttpClientFactory;
    private const string _responseToken = "next-token";

    [SetUp]
    public void SetUp()
    {
        _mockHttpClientFactory = Substitute.For<IHttpClientFactory>();
    }

    [Test]
    public async Task SearchAsync_WithValidInputAndNoSkipToken_ReturnsGroups()
    {
        // Arrange
        var groupProvider = CreateGroupProviderWithFixedResponse();

        // Act
        var result = await groupProvider.SearchAsync("test", null);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result.Page, Has.Count.EqualTo(2));
            Assert.That(result.SkipToken, Is.EqualTo(_responseToken));
            Assert.That(result.ErrorMessage, Is.Null);
        }
    }

    [Test]
    public async Task SearchAsync_WithValidSkipToken_PassesSkipToken()
    {
        // Arrange
        var groupProvider = CreateGroupProviderWithFixedResponse();

        // Act
        var result = await groupProvider.SearchAsync("test", "skip-token-123");

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result.Page, Has.Count.EqualTo(2));
            Assert.That(result.SkipToken, Is.EqualTo(_responseToken));
            Assert.That(result.ErrorMessage, Is.Null);
        }
    }

    [Test]
    public async Task SearchAsync_WithEmptySkipToken_HandlesCorrectly()
    {
        // Arrange
        var groupProvider = CreateGroupProviderWithFixedResponse();

        // Act
        var result = await groupProvider.SearchAsync("test", string.Empty);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result.Page, Has.Count.EqualTo(2));
            Assert.That(result.SkipToken, Is.EqualTo(_responseToken));
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
        var groupProvider = new EntraGroupSearchProvider(adminApiService);

        // Act
        var result = await groupProvider.SearchAsync("test", null);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result.Page, Is.Null);
            Assert.That(result.SkipToken, Is.Null);
            Assert.That(result.ErrorMessage, Is.Not.Null);
        }
    }

    [Test]
    public async Task SearchAsync_WhenNoResultsFound_ReturnsEmptyList()
    {
        // Arrange
        var groupProvider = CreateGroupProviderWithFixedResponse(new List<Group>(), null);

        // Act
        var result = await groupProvider.SearchAsync("nonexistent", null);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result.Page, Is.Empty);
            Assert.That(result.SkipToken, Is.Null);
            Assert.That(result.ErrorMessage, Is.Null);
        }
    }

    [Test]
    public async Task SearchAsync_WithSpecialSearchSymbols_EscapesSearchTerm()
    {
        // Arrange
        var handler = new MockHttpMessageHandler(HttpStatusCode.OK, null);
        var httpClient = new HttpClient(handler)
        {
            BaseAddress = new Uri("http://localhost:5300")
        };
        _mockHttpClientFactory.CreateClient(AdminApiService.HttpClientName).Returns(httpClient);

        var adminApiService = new AdminApiService(_mockHttpClientFactory);
        var groupProvider = new EntraGroupSearchProvider(adminApiService);

        // Act
        await groupProvider.SearchAsync("o'test", null);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(handler.CapturedRequests, Has.Count.EqualTo(1));
            Assert.That(handler.CapturedRequests[0].Url, Does.Contain("search/displayName/o%27test?skipToken="));
        }
    }

    [Test]
    public async Task SearchAsync_WithSpecialSkipTokenSymbols_EscapesSearchTerm()
    {
        // Arrange
        var handler = new MockHttpMessageHandler(HttpStatusCode.OK, null);
        var httpClient = new HttpClient(handler)
        {
            BaseAddress = new Uri("http://localhost:5300")
        };
        _mockHttpClientFactory.CreateClient(AdminApiService.HttpClientName).Returns(httpClient);

        var adminApiService = new AdminApiService(_mockHttpClientFactory);
        var groupProvider = new EntraGroupSearchProvider(adminApiService);

        // Act
        await groupProvider.SearchAsync("test", "abc#def");

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(handler.CapturedRequests, Has.Count.EqualTo(1));
            Assert.That(handler.CapturedRequests[0].Url, Does.Contain("search/displayName/test?skipToken=abc%23def"));
        }
    }

    private EntraGroupSearchProvider CreateGroupProviderWithFixedResponse(List<Group> groups = null, string skipToken = _responseToken)
    {
        var fixedGroups = groups ?? new List<Group>
        {
            new() { Id = "group1", DisplayName = "Test Group 1" },
            new() { Id = "group2", DisplayName = "Test Group 2" }
        };
        var responseData = new GroupResponse
        {
            Groups = fixedGroups,
            SkipToken = skipToken
        };
        var httpClient = new HttpClient(new MockHttpMessageHandler(HttpStatusCode.OK, responseData))
        {
            BaseAddress = new Uri("http://localhost:5300")
        };
        _mockHttpClientFactory.CreateClient(AdminApiService.HttpClientName).Returns(httpClient);

        var adminApiService = new AdminApiService(_mockHttpClientFactory);
        return new EntraGroupSearchProvider(adminApiService);
    }
}
