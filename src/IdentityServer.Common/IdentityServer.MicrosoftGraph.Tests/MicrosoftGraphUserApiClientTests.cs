using System.Net;
using System.Net.Http.Json;
using System.Web;
using Microsoft.Extensions.Logging.Abstractions;
using NSubstitute;
using IdentityServer.Abstraction.Entities.EntraEntities;
using IdentityServer.Tests.Common;

namespace IdentityServer.MicrosoftGraph.Tests;

[TestFixture]
public class MicrosoftGraphUserApiClientTests
{
    private IHttpClientFactory _httpClientFactory;
    private MicrosoftGraphUserApiClient _client;

    [SetUp]
    public void SetUp()
    {
        _httpClientFactory = Substitute.For<IHttpClientFactory>();
        _client = new MicrosoftGraphUserApiClient(_httpClientFactory, NullLogger<MicrosoftGraphUserApiClient>.Instance);
    }

    [TestCase(true)]
    [TestCase(false)]
    [TestCase(null)]
    public async Task GetUserByObjectIdAsync_WhenUserIsFound_ReturnsUserResponse(bool? accountEnabled)
    {
        // Arrange
        var userObjectId = "test-user-id";
        var user = new User { OId = userObjectId, DisplayName = "Test User", AccountEnabled = accountEnabled };
        var client = new HttpClient(new MockHttpMessageHandler(HttpStatusCode.OK, user));
        _httpClientFactory.CreateClient(Arg.Any<string>()).Returns(client);

        // Act
        var result = await _client.GetUserByObjectIdAsync(userObjectId);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result, Is.Not.Null);
            Assert.That(result.Users, Has.Count.EqualTo(1));
            Assert.That(result.Users[0].OId, Is.EqualTo(userObjectId));
            Assert.That(result.Users[0].DisplayName, Is.EqualTo(user.DisplayName));
        }
    }

    [Test]
    public async Task GetUserByObjectIdAsync_WhenUserNotFound_ReturnsEmptyResponse()
    {
        // Arrange
        var userObjectId = "nonexistent-user";
        var httpClient = new HttpClient(new MockHttpMessageHandler(HttpStatusCode.NotFound, ""));
        _httpClientFactory.CreateClient(Arg.Any<string>()).Returns(httpClient);

        // Act
        var result = await _client.GetUserByObjectIdAsync(userObjectId);

        // Assert
        Assert.That(result.Users, Is.Empty);
    }

    [Test]
    public void GetUserByObjectIdAsync_WhenUserIdIsNull_ThrowsArgumentNullException()
    {
        // Act & Assert
        Assert.ThrowsAsync<ArgumentNullException>(() => _client.GetUserByObjectIdAsync(null!));
    }

    [Test]
    public void GetUserByObjectIdAsync_WhenUserIdIsEmpty_ThrowsArgumentException()
    {
        // Act & Assert
        Assert.ThrowsAsync<ArgumentException>(() => _client.GetUserByObjectIdAsync(string.Empty));
    }

    [Test]
    public void GetUserByObjectIdAsync_OnHttpError_ThrowsHttpRequestException()
    {
        // Arrange
        var userObjectId = "test-user-id";
        var httpClient = new HttpClient(new MockHttpMessageHandler(HttpStatusCode.InternalServerError, ""));
        _httpClientFactory.CreateClient(Arg.Any<string>()).Returns(httpClient);

        // Act & Assert
        Assert.ThrowsAsync<HttpRequestException>(async () => await _client.GetUserByObjectIdAsync(userObjectId));
    }

    [Test]
    public async Task GetUsersByObjectIdsAsync_WithEmptyList_ReturnsEmptyResponse()
    {
        // Arrange
        var userIds = new List<string>();
        var httpClient = new HttpClient(new MockHttpMessageHandler(HttpStatusCode.OK, new UserResponse()));
        _httpClientFactory.CreateClient(Arg.Any<string>()).Returns(httpClient);

        // Act
        var result = await _client.GetUsersByObjectIdsAsync(userIds);

        // Assert
        Assert.That(result.Users, Is.Empty);
    }

    [Test]
    public async Task GetUsersByObjectIdsAsync_WithDuplicateUserIds_DeduplicatesAndMakesOneRequest()
    {
        // Arrange
        var userId = "duplicate-user-id";
        var userIds = new List<string> { userId, userId, userId };
        var userResponse = new UserResponse
        {
            Users = new List<User> { new() { OId = userId, DisplayName = "Test User" } }
        };
        MockHttpMessageHandler handler = new(HttpStatusCode.OK, userResponse);
        var httpClient = new HttpClient(handler);
        _httpClientFactory.CreateClient(Arg.Any<string>()).Returns(httpClient);

        // Act
        var result = await _client.GetUsersByObjectIdsAsync(userIds);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result.Users, Has.Count.EqualTo(userResponse.Users.Count));
            Assert.That(result.Users[0].OId, Is.EqualTo(userId));
            // Verify only one request was made
            Assert.That(handler.CapturedRequests, Has.Count.EqualTo(1));
        }
    }

    [Test]
    public async Task GetUsersByObjectIdsAsync_WithCaseInsensitiveDuplicates_DeduplicatesAndMakesOneRequest()
    {
        // Arrange
        var userId = "test-user-id";
        var userIds = new List<string> { userId.ToUpper(), userId.ToLower(), userId };
        var userResponse = new UserResponse
        {
            Users = new List<User> { new() { OId = userId, DisplayName = "Test User" } }
        };
        MockHttpMessageHandler handler = new(HttpStatusCode.OK, userResponse);
        var httpClient = new HttpClient(handler);
        _httpClientFactory.CreateClient(Arg.Any<string>()).Returns(httpClient);

        // Act
        var result = await _client.GetUsersByObjectIdsAsync(userIds);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result.Users, Has.Count.EqualTo(userResponse.Users.Count));
            // Verify only one request was made
            Assert.That(handler.CapturedRequests, Has.Count.EqualTo(1));
        }
    }

    [Test]
    public async Task GetUsersByObjectIdsAsync_With30Users_BatchesInto2RequestsOf15Each()
    {
        // Arrange
        var batchSize = 15;
        var batchCount = 2;
        var userIdCount = batchSize * batchCount;
        var userIds = Enumerable.Range(1, userIdCount).Select(i => $"user-{i}").ToList();
        var userResponse = new UserResponse
        {
            Users = userIds.Take(batchSize).Select(id => new User { OId = id, DisplayName = $"User {id}" }).ToList()
        };
        MockHttpMessageHandler handler = new(HttpStatusCode.OK, userResponse);
        var httpClient = new HttpClient(handler);
        _httpClientFactory.CreateClient(Arg.Any<string>()).Returns(httpClient);

        // Act
        var result = await _client.GetUsersByObjectIdsAsync(userIds);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(handler.CapturedRequests, Has.Count.EqualTo(batchCount));
            Assert.That(result.Users, Has.Count.EqualTo(userIdCount));
        }
    }

    [Test]
    public void GetUsersByObjectIdsAsync_WhenUserIdsIsNull_ThrowsArgumentNullException()
    {
        // Act & Assert
        Assert.ThrowsAsync<ArgumentNullException>(() => _client.GetUsersByObjectIdsAsync(null!));
    }

    [Test]
    public async Task GetUserOnPremisePropertiesAsync_WhenUserExists_ReturnsProperties()
    {
        // Arrange
        var userObjectId = "test-user-id";
        var properties = new UserOnPremisePropertiesResponse { OnPremisesSamAccountName = "test-sam-account" };
        var httpClient = new HttpClient(new MockHttpMessageHandler(HttpStatusCode.OK, properties));
        _httpClientFactory.CreateClient(Arg.Any<string>()).Returns(httpClient);

        // Act
        var result = await _client.GetUserOnPremisePropertiesAsync(userObjectId);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result, Is.Not.Null);
            Assert.That(result!.OnPremisesSamAccountName, Is.EqualTo(properties.OnPremisesSamAccountName));
        }
    }

    [Test]
    public async Task GetUserOnPremisePropertiesAsync_WhenUserNotFound_ReturnsNull()
    {
        // Arrange
        var userObjectId = "nonexistent-user";
        var httpClient = new HttpClient(new MockHttpMessageHandler(HttpStatusCode.NotFound, ""));
        _httpClientFactory.CreateClient(Arg.Any<string>()).Returns(httpClient);

        // Act
        var result = await _client.GetUserOnPremisePropertiesAsync(userObjectId);

        // Assert
        Assert.That(result, Is.Null);
    }

    [Test]
    public void GetUserOnPremisePropertiesAsync_WhenUserIdIsNull_ThrowsArgumentNullException()
    {
        // Act & Assert
        Assert.ThrowsAsync<ArgumentNullException>(() => _client.GetUserOnPremisePropertiesAsync(null!));
    }

    [Test]
    public void GetUserOnPremisePropertiesAsync_WhenUserIdIsEmpty_ThrowsArgumentException()
    {
        // Act & Assert
        Assert.ThrowsAsync<ArgumentException>(() => _client.GetUserOnPremisePropertiesAsync(string.Empty));
    }

    [Test]
    public async Task GetUserPropertiesAsync_WhenUserExists_ReturnsAdditionalProperties()
    {
        // Arrange
        var userObjectId = "test-user-id";
        var properties = new UserAdditionalPropertiesResponse { DisplayName = "Test User" };
        var httpClient = new HttpClient(new MockHttpMessageHandler(HttpStatusCode.OK, properties));
        _httpClientFactory.CreateClient(Arg.Any<string>()).Returns(httpClient);

        // Act
        var result = await _client.GetUserPropertiesAsync(userObjectId);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result, Is.Not.Null);
            Assert.That(result!.DisplayName, Is.EqualTo(properties.DisplayName));
        }
    }

    [Test]
    public async Task GetUserPropertiesAsync_WhenUserNotFound_ReturnsNull()
    {
        // Arrange
        var userObjectId = "nonexistent-user";
        var httpClient = new HttpClient(new MockHttpMessageHandler(HttpStatusCode.NotFound, ""));
        _httpClientFactory.CreateClient(Arg.Any<string>()).Returns(httpClient);

        // Act
        var result = await _client.GetUserPropertiesAsync(userObjectId);

        // Assert
        Assert.That(result, Is.Null);
    }

    [Test]
    public void GetUserPropertiesAsync_WhenUserIdIsNull_ThrowsArgumentNullException()
    {
        // Act & Assert
        Assert.ThrowsAsync<ArgumentNullException>(() => _client.GetUserPropertiesAsync(null!));
    }

    [Test]
    public void GetUserPropertiesAsync_WhenUserIdIsEmpty_ThrowsArgumentException()
    {
        // Act & Assert
        Assert.ThrowsAsync<ArgumentException>(() => _client.GetUserPropertiesAsync(string.Empty));
    }

    [Test]
    public async Task SearchUsersByDisplayNameAsync_WhenUsersAreFound_ReturnsUsers()
    {
        // Arrange
        var displayName = "Test";
        var userResponse = new UserResponse
        {
            Users = new List<User> { new() { OId = "1", DisplayName = "Test User" } }
        };
        var httpClient = new HttpClient(new MockHttpMessageHandler(HttpStatusCode.OK, userResponse));
        _httpClientFactory.CreateClient(Arg.Any<string>()).Returns(httpClient);

        // Act
        var result = await _client.SearchUsersByDisplayNameAsync(displayName);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result, Is.Not.Null);
            Assert.That(result.Users, Has.Count.EqualTo(1));
            Assert.That(result.Users[0].DisplayName, Is.EqualTo(userResponse.Users[0].DisplayName));
        }
    }

    [Test]
    public async Task SearchUsersByDisplayNameAsync_WithSpacesInDisplayName_EncodesQueryParameterCorrectly()
    {
        // Arrange
        var displayName = "Test User";
        var userResponse = new UserResponse
        {
            Users = new List<User> { new() { OId = "1", DisplayName = displayName } }
        };
        MockHttpMessageHandler handler = new(HttpStatusCode.OK, userResponse);
        var httpClient = new HttpClient(handler);
        _httpClientFactory.CreateClient(Arg.Any<string>()).Returns(httpClient);

        // Act
        var result = await _client.SearchUsersByDisplayNameAsync(displayName);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result, Is.Not.Null);
            Assert.That(result.Users, Has.Count.EqualTo(1));
            Assert.That(result.Users[0].DisplayName, Is.EqualTo(displayName));
            // Verify query encoding
            var expectedEncodedQuery = HttpUtility.UrlEncode($"\"displayName:{displayName}\"");
            Assert.That(handler.CapturedRequests.Any(req => req.Url.Contains(expectedEncodedQuery)), Is.True);
        }
    }

    [Test]
    public async Task SearchUsersByDisplayNameAsync_WithBackslashInDisplayName_EscapesBackslashes()
    {
        // Arrange
        var displayName = @"Test\User";
        var userResponse = new UserResponse
        {
            Users = new List<User> { new() { OId = "1", DisplayName = displayName } }
        };
        MockHttpMessageHandler handler = new(HttpStatusCode.OK, userResponse);
        var httpClient = new HttpClient(handler);
        _httpClientFactory.CreateClient(Arg.Any<string>()).Returns(httpClient);

        // Act
        var result = await _client.SearchUsersByDisplayNameAsync(displayName);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result, Is.Not.Null);
            // Verify backslash was double-escaped (first to \\ then URL-encoded to %5c%5c)
            var capturedRequest = handler.CapturedRequests.First();
            Assert.That(capturedRequest.Url, Does.Contain("Test%5c%5cUser"));
        }
    }

    [Test]
    public async Task SearchUsersByDisplayNameAsync_WithQuotesInDisplayName_EscapesQuotes()
    {
        // Arrange
        var displayName = "Test\"User";
        var userResponse = new UserResponse
        {
            Users = new List<User> { new() { OId = "1", DisplayName = displayName } }
        };
        MockHttpMessageHandler handler = new(HttpStatusCode.OK, userResponse);
        var httpClient = new HttpClient(handler);
        _httpClientFactory.CreateClient(Arg.Any<string>()).Returns(httpClient);

        // Act
        var result = await _client.SearchUsersByDisplayNameAsync(displayName);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result, Is.Not.Null);
            // Verify quotes were escaped (\" becomes %5c%22 in URL encoding)
            var capturedRequest = handler.CapturedRequests.First();
            Assert.That(capturedRequest.Url, Does.Contain("Test%5c%22User"));
        }
    }

    [Test]
    public async Task SearchUsersByDisplayNameAsync_WhenNoUsersFound_ReturnsEmptyResponse()
    {
        // Arrange
        var displayName = "Nonexistent";
        var userResponse = new UserResponse { Users = new List<User>() };
        var httpClient = new HttpClient(new MockHttpMessageHandler(HttpStatusCode.OK, userResponse));
        _httpClientFactory.CreateClient(Arg.Any<string>()).Returns(httpClient);

        // Act
        var result = await _client.SearchUsersByDisplayNameAsync(displayName);

        // Assert
        Assert.That(result.Users, Is.Empty);
    }

    [Test]
    public async Task SearchUsersByDisplayNameAsync_Always_AddsPreferModernSearchHeader()
    {
        // Arrange
        var displayName = "Test";
        var userResponse = new UserResponse
        {
            Users = new List<User> { new() { OId = "1", DisplayName = displayName } }
        };
        MockHttpMessageHandler handler = new(HttpStatusCode.OK, userResponse);
        var httpClient = new HttpClient(handler);
        _httpClientFactory.CreateClient(Arg.Any<string>()).Returns(httpClient);

        // Act
        _ = await _client.SearchUsersByDisplayNameAsync(displayName);

        // Assert
        var capturedRequest = handler.CapturedRequests.First();
        using (Assert.EnterMultipleScope())
        {
            Assert.That(capturedRequest.Headers.ContainsKey("Prefer"), Is.True);
            Assert.That(capturedRequest.Headers["Prefer"], Does.Contain("legacySearch=false"));
        }
    }

    [Test]
    public void SearchUsersByDisplayNameAsync_OnHttpError_ThrowsHttpRequestException()
    {
        // Arrange
        var displayName = "Test";
        var httpClient = new HttpClient(new MockHttpMessageHandler(HttpStatusCode.Unauthorized, ""));
        _httpClientFactory.CreateClient(Arg.Any<string>()).Returns(httpClient);

        // Act & Assert
        Assert.ThrowsAsync<HttpRequestException>(async () => await _client.SearchUsersByDisplayNameAsync(displayName));
    }

    [Test]
    public void SearchUsersByDisplayNameAsync_WhenDisplayNameIsNull_ThrowsArgumentNullException()
    {
        // Act & Assert
        Assert.ThrowsAsync<ArgumentNullException>(() => _client.SearchUsersByDisplayNameAsync(null!));
    }

    [Test]
    public void SearchUsersByDisplayNameAsync_WhenDisplayNameIsEmpty_ThrowsArgumentException()
    {
        // Act & Assert
        Assert.ThrowsAsync<ArgumentException>(() => _client.SearchUsersByDisplayNameAsync(string.Empty));
    }

    [Test]
    public async Task GetUserMembershipInGroups_WhenUserIsMember_ReturnsGroups()
    {
        // Arrange
        var userId = "test-user-id";
        var groupIds = new List<string> { "group-id-1", "group-id-2" };
        var checkMemberGroupsResponse = new { value = new[] { "group-id-1" } };

        var httpClient = new HttpClient(new MockHttpMessageHandler(HttpStatusCode.OK, checkMemberGroupsResponse));
        _httpClientFactory.CreateClient(Arg.Any<string>()).Returns(httpClient);

        // Act
        var result = await _client.GetUserMembershipInGroups(userId, groupIds);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result, Is.Not.Null);
            Assert.That(result.Groups, Has.Count.EqualTo(1));
            Assert.That(result.Groups[0].Id, Is.EqualTo("group-id-1"));
        }
    }

    [Test]
    public async Task GetUserMembershipInGroups_WhenGroupIdFilterIsNull_ReturnsEmptyResponse()
    {
        // Arrange
        var userId = "test-user-id";
        var httpClient = new HttpClient(new MockHttpMessageHandler(HttpStatusCode.OK, new { value = Array.Empty<string>() }));
        _httpClientFactory.CreateClient(Arg.Any<string>()).Returns(httpClient);

        // Act
        var result = await _client.GetUserMembershipInGroups(userId, null!);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result, Is.Not.Null);
            Assert.That(result.Groups, Is.Empty);
        }
    }

    [Test]
    public async Task GetUserMembershipInGroups_WhenGroupIdFilterIsEmpty_ReturnsEmptyResponse()
    {
        // Arrange
        var userId = "test-user-id";
        var httpClient = new HttpClient(new MockHttpMessageHandler(HttpStatusCode.OK, new { value = Array.Empty<string>() }));
        _httpClientFactory.CreateClient(Arg.Any<string>()).Returns(httpClient);

        // Act
        var result = await _client.GetUserMembershipInGroups(userId, Enumerable.Empty<string>());

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result, Is.Not.Null);
            Assert.That(result.Groups, Is.Empty);
        }
    }

    [Test]
    public void GetUserMembershipInGroups_WhenUserIdIsNull_ThrowsArgumentNullException()
    {
        // Arrange
        var groupIds = new List<string> { "group-1" };

        // Act & Assert
        Assert.ThrowsAsync<ArgumentNullException>(() => _client.GetUserMembershipInGroups(null!, groupIds));
    }

    [Test]
    public void GetUserMembershipInGroups_WhenUserIdIsEmpty_ThrowsArgumentException()
    {
        // Arrange
        var groupIds = new List<string> { "group-1" };

        // Act & Assert
        Assert.ThrowsAsync<ArgumentException>(() => _client.GetUserMembershipInGroups(string.Empty, groupIds));
    }

    [Test]
    public async Task GetUserMembershipInGroups_WithGroupIdFilterHaving20Items_ReturnsGroups()
    {
        // Arrange
        var userId = "test-user-id";
        var groupIds = Enumerable.Range(1, 20).Select(i => $"group-id-{i}").ToList();
        var checkMemberGroupsResponse = new { value = new[] { "group-id-1", "group-id-2" } };
        var expected = new[] { "group-id-1", "group-id-2" };

        var httpClient = new HttpClient(new MockHttpMessageHandler(HttpStatusCode.OK, checkMemberGroupsResponse));
        _httpClientFactory.CreateClient(Arg.Any<string>()).Returns(httpClient);

        // Act
        var result = await _client.GetUserMembershipInGroups(userId, groupIds);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result, Is.Not.Null);
            Assert.That(result.Groups, Has.Count.EqualTo(2));
            Assert.That(result.Groups.Select(g => g.Id), Is.EquivalentTo(expected));
        }
    }

    [Test]
    public async Task GetUserMembershipInGroups_WithGroupIdFilterHavingMoreThan20Items_ReturnsGroups()
    {
        // Arrange
        var userId = "test-user-id";
        var groupIds = Enumerable.Range(1, 25).Select(i => $"group-id-{i}").ToList();

        // Simulate API: first batch returns first 10, second batch returns next 5
        var batchResponses = new[]
        {
            new { value = groupIds.Take(10).ToArray() },
            new { value = groupIds.Skip(10).Take(5).ToArray() }
        };

        int callCount = 0;
        var handler = new MockHttpMessageHandler((request) =>
        {
            // Return different responses for each batch
            var response = callCount < batchResponses.Length
                ? batchResponses[callCount]
                : new { value = Array.Empty<string>() };
            callCount++;
            return new HttpResponseMessage(HttpStatusCode.OK)
            {
                Content = JsonContent.Create(response)
            };
        });

        var httpClient = new HttpClient(handler);
        _httpClientFactory.CreateClient(Arg.Any<string>()).Returns(httpClient);

        // Act
        var result = await _client.GetUserMembershipInGroups(userId, groupIds);

        // Assert
        var expected = groupIds.Take(15).ToArray();
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result, Is.Not.Null);
            Assert.That(result.Groups, Has.Count.EqualTo(15));
            Assert.That(result.Groups.Select(g => g.Id), Is.EquivalentTo(expected));
        }
    }

    [Test]
    public async Task GetUserMembershipInGroups_With45Groups_BatchesInto3RequestsOf20_20_5()
    {
        // Arrange
        var userId = "test-user-id";
        var groupIds = Enumerable.Range(1, 45).Select(i => $"group-id-{i}").ToList();
        var checkMemberGroupsResponse = new { value = Array.Empty<string>() };
        MockHttpMessageHandler handler = new(HttpStatusCode.OK, checkMemberGroupsResponse);
        var httpClient = new HttpClient(handler);
        _httpClientFactory.CreateClient(Arg.Any<string>()).Returns(httpClient);

        // Act
        var result = await _client.GetUserMembershipInGroups(userId, groupIds);

        // Assert
        // Should make 3 batches (20 + 20 + 5)
        Assert.That(handler.CapturedRequests, Has.Count.EqualTo(3));
    }

    [Test]
    public async Task GetUserMembershipInGroups_WithDuplicateCaseInsensitiveGroupIds_DeduplicatesAndMakesOneRequest()
    {
        // Arrange
        var userId = "test-user-id";
        var groupIds = new List<string> { "group-1", "group-1", "GROUP-1", "group-2" };
        var checkMemberGroupsResponse = new { value = new[] { "group-1" } };
        MockHttpMessageHandler handler = new(HttpStatusCode.OK, checkMemberGroupsResponse);
        var httpClient = new HttpClient(handler);
        _httpClientFactory.CreateClient(Arg.Any<string>()).Returns(httpClient);

        // Act
        var result = await _client.GetUserMembershipInGroups(userId, groupIds);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result.Groups, Has.Count.EqualTo(1));
            // Should only make 1 request since deduplicated to 2 unique groups
            Assert.That(handler.CapturedRequests, Has.Count.EqualTo(1));
        }
    }

    [Test]
    public async Task GetUserMembershipInGroups_Always_SendsPostRequest()
    {
        // Arrange
        var userId = "test-user-id";
        var groupIds = new List<string> { "group-1" };
        var checkMemberGroupsResponse = new { value = new[] { "group-1" } };
        MockHttpMessageHandler handler = new(HttpStatusCode.OK, checkMemberGroupsResponse);
        var httpClient = new HttpClient(handler);
        _httpClientFactory.CreateClient(Arg.Any<string>()).Returns(httpClient);

        // Act
        await _client.GetUserMembershipInGroups(userId, groupIds);

        // Assert
        var capturedRequest = handler.CapturedRequests.First();
        Assert.That(capturedRequest.Method, Is.EqualTo(HttpMethod.Post));
    }

    [Test]
    public async Task GetUserMembershipInGroups_Always_IncludesGroupIdsInRequestBody()
    {
        // Arrange
        var userId = "test-user-id";
        var groupIds = new List<string> { "group-1", "group-2" };
        var checkMemberGroupsResponse = new { value = new[] { "group-1" } };
        MockHttpMessageHandler handler = new(HttpStatusCode.OK, checkMemberGroupsResponse);
        var httpClient = new HttpClient(handler);
        _httpClientFactory.CreateClient(Arg.Any<string>()).Returns(httpClient);

        // Act
        await _client.GetUserMembershipInGroups(userId, groupIds);

        // Assert
        var capturedRequest = handler.CapturedRequests.First();
        using (Assert.EnterMultipleScope())
        {
            Assert.That(capturedRequest.Body, Does.Contain("group-1"));
            Assert.That(capturedRequest.Body, Does.Contain("group-2"));
        }
    }

    [Test]
    public void GetUserMembershipInGroups_OnHttpError_ThrowsHttpRequestException()
    {
        // Arrange
        var userId = "test-user-id";
        var groupIds = new List<string> { "group-1" };
        var httpClient = new HttpClient(new MockHttpMessageHandler(HttpStatusCode.InternalServerError, ""));
        _httpClientFactory.CreateClient(Arg.Any<string>()).Returns(httpClient);

        // Act & Assert
        Assert.ThrowsAsync<HttpRequestException>(async () => await _client.GetUserMembershipInGroups(userId, groupIds));
    }
}
