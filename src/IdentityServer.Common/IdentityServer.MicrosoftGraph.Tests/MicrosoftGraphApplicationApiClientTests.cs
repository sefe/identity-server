// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

using Microsoft.Extensions.Logging.Abstractions;
using NSubstitute;
using System.Net;
using IdentityServer.Abstraction.Entities.EntraEntities;
using IdentityServer.Tests.Common;

namespace IdentityServer.MicrosoftGraph.Tests;

[TestFixture]
public class MicrosoftGraphApplicationApiClientTests
{
    private IHttpClientFactory _httpClientFactory;
    private MicrosoftGraphApplicationApiClient _client;

    [SetUp]
    public void SetUp()
    {
        _httpClientFactory = Substitute.For<IHttpClientFactory>();
        _client = new MicrosoftGraphApplicationApiClient(_httpClientFactory, NullLogger<MicrosoftGraphApplicationApiClient>.Instance);
    }

    [Test]
    public async Task GetApplicationByAppIdAsync_ReturnsApplication_WhenApplicationIsFound()
    {
        // Arrange
        var appId = "test-app-id";
        var expectedApplication = new Application
        {
            Id = "object-id-123",
            AppId = appId,
            DisplayName = "Test Application"
        };

        var httpClient = new HttpClient(new MockHttpMessageHandler(HttpStatusCode.OK, expectedApplication));
        _httpClientFactory.CreateClient(Arg.Any<string>()).Returns(httpClient);

        // Act
        var result = await _client.GetApplicationByAppIdAsync(appId);

        // Assert
        Assert.That(result, Is.Not.Null);
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result.Id, Is.EqualTo(expectedApplication.Id));
            Assert.That(result.AppId, Is.EqualTo(expectedApplication.AppId));
            Assert.That(result.DisplayName, Is.EqualTo(expectedApplication.DisplayName));
        }
    }

    [Test]
    public async Task GetApplicationByAppIdAsync_ReturnsNull_WhenApplicationNotFound()
    {
        // Arrange
        var appId = "non-existent-app-id";
        var httpClient = new HttpClient(new MockHttpMessageHandler(HttpStatusCode.NotFound, ""));
        _httpClientFactory.CreateClient(Arg.Any<string>()).Returns(httpClient);

        // Act
        var result = await _client.GetApplicationByAppIdAsync(appId);

        // Assert
        Assert.That(result, Is.Null);
    }

    [Test]
    public void GetApplicationByAppIdAsync_ThrowsException_WhenResponseIsUnsuccessful()
    {
        // Arrange
        var appId = "test-app-id";
        var httpClient = new HttpClient(new MockHttpMessageHandler(HttpStatusCode.BadRequest, "Error"));
        _httpClientFactory.CreateClient(Arg.Any<string>()).Returns(httpClient);

        // Act & Assert
        Assert.ThrowsAsync<HttpRequestException>(() => _client.GetApplicationByAppIdAsync(appId));
    }

    [Test]
    public async Task GetApplicationByAppIdAsync_UsesCorrectRequestUrlAndMethod()
    {
        // Arrange
        var appId = "test-app-id";
        var expectedApplication = new Application
        {
            Id = "object-id-123",
            AppId = appId,
            DisplayName = "Test Application"
        };

        var handler = new MockHttpMessageHandler(HttpStatusCode.OK, expectedApplication);
        var httpClient = new HttpClient(handler)
        {
            BaseAddress = new Uri("https://graph.microsoft.com/")
        };
        _httpClientFactory.CreateClient(Arg.Any<string>()).Returns(httpClient);

        // Act
        await _client.GetApplicationByAppIdAsync(appId);

        // Assert
        Assert.That(handler.CapturedRequests, Has.Count.EqualTo(1));
        var capturedRequest = handler.CapturedRequests[0];
        using (Assert.EnterMultipleScope())
        {
            Assert.That(capturedRequest.Method, Is.EqualTo(HttpMethod.Get));
            Assert.That(capturedRequest.Url, Does.Contain($"/v1.0/applications(appId='{appId}')"));
            Assert.That(capturedRequest.Url, Does.Contain("$select=id,appId,displayName"));
        }
    }

    [Test]
    public void GetApplicationByAppIdAsync_ThrowsException_WhenResponseIsForbidden()
    {
        // Arrange
        var appId = "test-app-id";
        var httpClient = new HttpClient(new MockHttpMessageHandler(HttpStatusCode.Forbidden, "Forbidden"));
        _httpClientFactory.CreateClient(Arg.Any<string>()).Returns(httpClient);

        // Act & Assert
        Assert.ThrowsAsync<HttpRequestException>(() => _client.GetApplicationByAppIdAsync(appId));
    }

    [Test]
    [TestCase(HttpStatusCode.Unauthorized)]
    [TestCase(HttpStatusCode.InternalServerError)]
    public void GetApplicationByAppIdAsync_ThrowsException_WhenResponseHasErrorCode(HttpStatusCode code)
    {
        // Arrange
        var appId = "test-app-id";
        var httpClient = new HttpClient(new MockHttpMessageHandler(code, code.ToString()));
        _httpClientFactory.CreateClient(Arg.Any<string>()).Returns(httpClient);

        // Act & Assert
        Assert.ThrowsAsync<HttpRequestException>(() => _client.GetApplicationByAppIdAsync(appId));
    }

    [Test]
    public async Task GetApplicationByAppIdAsync_UsesGraphApplicationsClientName()
    {
        // Arrange
        var appId = "test-app-id";
        var expectedApplication = new Application
        {
            Id = "object-id-123",
            AppId = appId,
            DisplayName = "Test Application"
        };

        var httpClient = new HttpClient(new MockHttpMessageHandler(HttpStatusCode.OK, expectedApplication));
        _httpClientFactory.CreateClient(Arg.Any<string>()).Returns(httpClient);

        // Act
        await _client.GetApplicationByAppIdAsync(appId);

        // Assert
        _httpClientFactory.Received(1).CreateClient(Constants.HttpClientNames.GraphApplicationsClientName);
    }
}
