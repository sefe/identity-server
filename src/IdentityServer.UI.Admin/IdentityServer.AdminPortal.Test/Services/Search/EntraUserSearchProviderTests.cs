using NSubstitute;
using System.Net;
using IdentityServer.Abstraction.Entities.EntraEntities;
using IdentityServer.AdminPortal.Web.Services;
using IdentityServer.AdminPortal.Web.Services.Search;
using IdentityServer.Tests.Common;

namespace IdentityServer.AdminPortal.Test.Services.Search;

[TestFixture]
public class EntraUserSearchProviderTests
{
    private IHttpClientFactory _mockHttpClientFactory;
    private const string _responseToken = "next-token";

    [SetUp]
    public void SetUp()
    {
        _mockHttpClientFactory = Substitute.For<IHttpClientFactory>();
    }

    private (EntraUserSearchProvider, MockHttpMessageHandler) CreateUserProviderWithFixedResponse(List<User> users = null)
    {
        var fixedUsers = users ?? new List<User>
        {
            new() { OId = "user1-oid", DisplayName = "John Doe", AccountEnabled = true },
            new() { OId = "user2-oid", DisplayName = "John Smith", AccountEnabled = true }
        };
        var responseData = new UserResponse
        {
            Users = fixedUsers,
            SkipToken = _responseToken
        };

        var handler = new MockHttpMessageHandler(HttpStatusCode.OK, responseData);
        var httpClient = new HttpClient(handler)
        {
            BaseAddress = new Uri("http://localhost:5300")
        };
        _mockHttpClientFactory.CreateClient(AdminApiService.HttpClientName).Returns(httpClient);

        var adminApiService = new AdminApiService(_mockHttpClientFactory);
        return (new EntraUserSearchProvider(adminApiService), handler);
    }

    [TestCase("not-a-guid")]
    [TestCase("John")]
    [TestCase("71df9928-6b4d-42f9-857f-aa4c1f89b9")] //almost guid without 2 chars
    public async Task SearchAsync_WithDisplayNameSearch_CallsSearchAndReturnsUsers(string searchTerm)
    {
        // Arrange
        (var userProvider, var handler) = CreateUserProviderWithFixedResponse();

        // Act
        var result = await userProvider.SearchAsync(searchTerm, null);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(handler.CapturedRequests, Has.Count.EqualTo(1));
            Assert.That(handler.CapturedRequests[0].Url, Does.Contain($"search/displayName/{searchTerm}"));
            Assert.That(result.Page, Has.Count.EqualTo(2));
            Assert.That(result.SkipToken, Is.Null);
            Assert.That(result.ErrorMessage, Is.Null);
        }
    }

    [Test]
    public async Task SearchAsync_WithDisplayNameSpecialSymbolsSearch_CallsSearchAndReturnsUsers()
    {
        // Arrange
        (var userProvider, var handler) = CreateUserProviderWithFixedResponse();

        // Act
        await userProvider.SearchAsync("o$john", null);

        // Assert
        Assert.That(handler.CapturedRequests[0].Url, Does.Contain("search/displayName/o%24john"));
    }

    [TestCase("71df9928-6b4d-42f9-857f-aa4c1f89b9c1")] // lower case
    [TestCase("71DF9928-6B4D-42F9-857F-AA4C1F89B9C1")] //upper case
    public async Task SearchAsync_WithValidGuid_CallsGetUserById(string userId)
    {
        // Arrange
        (var userProvider, var handler) = CreateUserProviderWithFixedResponse();

        // Act
        await userProvider.SearchAsync(userId, null);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(handler.CapturedRequests, Has.Count.EqualTo(1));
            Assert.That(handler.CapturedRequests[0].Url, Does.Contain($"api/user/{userId}"));
        }
    }

    [Test]
    public async Task SearchAsync_WithEmptySearchValue_CallsSearch()
    {
        // Arrange
        (var userProvider, var handler) = CreateUserProviderWithFixedResponse();

        // Act
        await userProvider.SearchAsync(string.Empty, null);

        // Assert
        Assert.That(handler.CapturedRequests[0].Url, Does.EndWith($"api/user/search/displayName/"));

    }

    [Test]
    public async Task SearchAsync_WithErrorFromAdminApi_ReturnsErrorMessage()
    {
        // Arrange
        var httpClient = new HttpClient(new MockHttpMessageHandler(HttpStatusCode.OK, null)); // fails to work without a Base Url configured
        _mockHttpClientFactory.CreateClient(AdminApiService.HttpClientName).Returns(httpClient);

        var adminApiService = new AdminApiService(_mockHttpClientFactory);
        var userProvider = new EntraUserSearchProvider(adminApiService);

        // Act
        var result = await userProvider.SearchAsync("test", null);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result.Page, Is.Empty);
            Assert.That(result.SkipToken, Is.Null);
            Assert.That(result.ErrorMessage, Is.Not.Null);
        }
    }

    [Test]
    public async Task SearchAsync_WhenNoResultsFound_ReturnsEmptyList()
    {
        // Arrange
        (var userProvider, _) = CreateUserProviderWithFixedResponse(new List<User>());

        // Act
        var result = await userProvider.SearchAsync("nonexistent", null);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result.Page, Is.Empty);
            Assert.That(result.SkipToken, Is.Null);
            Assert.That(result.ErrorMessage, Is.Null);
        }
    }
}
