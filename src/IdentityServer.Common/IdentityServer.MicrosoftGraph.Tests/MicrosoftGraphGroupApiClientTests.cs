using Microsoft.Extensions.Logging.Abstractions;
using NSubstitute;
using System.Net;
using System.Net.Http.Json;
using System.Web;
using IdentityServer.Abstraction.Entities.EntraEntities;
using IdentityServer.Tests.Common;

namespace IdentityServer.MicrosoftGraph.Tests;

[TestFixture]
public class MicrosoftGraphGroupApiClientTests
{
    private IHttpClientFactory _httpClientFactory;
    private MicrosoftGraphGroupApiClient _client;

    [SetUp]
    public void SetUp()
    {
        _httpClientFactory = Substitute.For<IHttpClientFactory>();
        _client = new MicrosoftGraphGroupApiClient(_httpClientFactory, NullLogger<MicrosoftGraphGroupApiClient>.Instance);
    }

    [Test]
    public async Task GetGroupByObjectIdAsync_ReturnsGroupResponse_WhenGroupIsFound()
    {
        // Arrange
        var groupId = Guid.NewGuid();
        var group = new Group { Id = groupId.ToString(), DisplayName = "Test Group" };
        var httpClient = new HttpClient(new MockHttpMessageHandler(HttpStatusCode.OK, group));
        _httpClientFactory.CreateClient(Arg.Any<string>()).Returns(httpClient);

        // Act
        var result = await _client.GetGroupByObjectIdAsync(groupId);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result, Is.Not.Null);
            Assert.That(result.Groups, Has.Count.EqualTo(1));
            Assert.That(result.Groups[0].Id, Is.EqualTo(groupId.ToString()));
            Assert.That(result.Groups[0].DisplayName, Is.EqualTo("Test Group"));
        }
    }

    [Test]
    public async Task GetGroupByObjectIdAsync_ReturnsEmptyResponse_WhenGroupNotFound()
    {
        // Arrange
        var groupId = Guid.NewGuid();
        var httpClient = new HttpClient(new MockHttpMessageHandler(HttpStatusCode.NotFound, ""));
        _httpClientFactory.CreateClient(Arg.Any<string>()).Returns(httpClient);

        // Act
        var result = await _client.GetGroupByObjectIdAsync(groupId);

        // Assert
        Assert.That(result.Groups, Is.Empty);
    }

    [Test]
    public async Task GetGroupByObjectIdAsync_BuildsCorrectRelativePath()
    {
        // Arrange
        var groupId = Guid.NewGuid();
        var group = new Group { Id = groupId.ToString(), DisplayName = "Test Group" };
        MockHttpMessageHandler handler = new(HttpStatusCode.OK, group);
        var httpClient = new HttpClient(handler);
        _httpClientFactory.CreateClient(Arg.Any<string>()).Returns(httpClient);

        // Act
        await _client.GetGroupByObjectIdAsync(groupId);

        // Assert
        var capturedRequest = handler.CapturedRequests.First();
        using (Assert.EnterMultipleScope())
        {
            Assert.That(capturedRequest.Url, Does.Contain($"/groups/{groupId}"));
            Assert.That(capturedRequest.Url, Does.Contain("displayName"));
            Assert.That(capturedRequest.Url, Does.Contain("id"));
        }
    }

    [Test]
    public async Task GetGroupsByObjectIdsAsync_ReturnsEmptyResponse_WhenEmptyList()
    {
        // Arrange
        var groupIds = new List<Guid>();
        var httpClient = new HttpClient(new MockHttpMessageHandler(HttpStatusCode.OK, new GroupResponse()));
        _httpClientFactory.CreateClient(Arg.Any<string>()).Returns(httpClient);

        // Act
        var result = await _client.GetGroupsByObjectIdsAsync(groupIds);

        // Assert
        Assert.That(result.Groups, Is.Empty);
    }

    [Test]
    public async Task GetGroupsByObjectIdsAsync_DeduplicatesGroupIds()
    {
        // Arrange
        var groupId = Guid.NewGuid();
        var groupIds = new List<Guid> { groupId, groupId, groupId };
        var groupResponse = new GroupResponse
        {
            Groups = new List<Group> { new() { Id = groupId.ToString(), DisplayName = "Test Group" } }
        };
        MockHttpMessageHandler handler = new(HttpStatusCode.OK, groupResponse);
        var httpClient = new HttpClient(handler);
        _httpClientFactory.CreateClient(Arg.Any<string>()).Returns(httpClient);

        // Act
        var result = await _client.GetGroupsByObjectIdsAsync(groupIds);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result.Groups, Has.Count.EqualTo(1));
            Assert.That(result.Groups[0].Id, Is.EqualTo(groupId.ToString()));
            // Verify only one request was made
            Assert.That(handler.CapturedRequests, Has.Count.EqualTo(1));
        }
    }

    [Test]
    public async Task GetGroupsByObjectIdsAsync_DeduplicatesCaseInsensitive()
    {
        // Arrange
        var groupId = Guid.NewGuid();
        var groupIdUpper = Guid.Parse(groupId.ToString().ToUpper());
        var groupIdLower = Guid.Parse(groupId.ToString().ToLower());
        var groupIds = new List<Guid> { groupIdUpper, groupIdLower, groupId };
        var groupResponse = new GroupResponse
        {
            Groups = new List<Group> { new() { Id = groupId.ToString(), DisplayName = "Test Group" } }
        };
        MockHttpMessageHandler handler = new(HttpStatusCode.OK, groupResponse);
        var httpClient = new HttpClient(handler);
        _httpClientFactory.CreateClient(Arg.Any<string>()).Returns(httpClient);

        // Act
        var result = await _client.GetGroupsByObjectIdsAsync(groupIds);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result.Groups, Has.Count.EqualTo(1));
            // Verify only one request was made
            Assert.That(handler.CapturedRequests, Has.Count.EqualTo(1));
        }
    }

    [Test]
    public async Task GetGroupsByObjectIdsAsync_BatchesRequestsAt15Groups()
    {
        // Arrange
        var groupIds = Enumerable.Range(1, 30).Select(_ => Guid.NewGuid()).ToList();
        var groupResponse = new GroupResponse
        {
            Groups = groupIds.Take(15).Select(id => new Group { Id = id.ToString(), DisplayName = $"Group {id}" }).ToList()
        };
        MockHttpMessageHandler handler = new(HttpStatusCode.OK, groupResponse);
        var httpClient = new HttpClient(handler);
        _httpClientFactory.CreateClient(Arg.Any<string>()).Returns(httpClient);

        // Act
        var result = await _client.GetGroupsByObjectIdsAsync(groupIds);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            // Should make 2 batches (15 + 15)
            Assert.That(handler.CapturedRequests, Has.Count.EqualTo(2));
            // Should return results from both batches
            Assert.That(result.Groups, Has.Count.EqualTo(30));
        }
    }

    [Test]
    public async Task GetGroupsByObjectIdsAsync_ReturnsGroups_WhenMultipleBatches()
    {
        // Arrange
        var groupsToRetrieveCount = 45;
        var batchSize = 15;
        var groupIds = Enumerable.Range(1, groupsToRetrieveCount).Select(_ => Guid.NewGuid()).ToList();

        // Simulate API: each batch returns the corresponding groups
        var batchResponses = groupIds
         .Chunk(batchSize)
            .Select(chunk => new GroupResponse
            {
                Groups = chunk.Select(id => new Group { Id = id.ToString(), DisplayName = $"Group {id}" }).ToList()
            })
            .ToArray();
        var expectedBatchCount = batchResponses.Length;

        int callCount = 0;
        var handler = new MockHttpMessageHandler((request) =>
            {
                // Return different responses for each batch
                var response = callCount < batchResponses.Length
                          ? batchResponses[callCount]
                     : new GroupResponse();
                callCount++;
                return new HttpResponseMessage(HttpStatusCode.OK)
                {
                    Content = JsonContent.Create(response)
                };
            });

        var httpClient = new HttpClient(handler);
        _httpClientFactory.CreateClient(Arg.Any<string>()).Returns(httpClient);

        // Act
        var result = await _client.GetGroupsByObjectIdsAsync(groupIds);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result, Is.Not.Null);
            Assert.That(handler.CapturedRequests, Has.Count.EqualTo(expectedBatchCount));
            Assert.That(result.Groups, Has.Count.EqualTo(groupsToRetrieveCount));
        }
    }

    [Test]
    public async Task GetGroupsByObjectIdsAsync_BuildsCorrectFilterQuery()
    {
        // Arrange
        var groupId1 = Guid.NewGuid();
        var groupId2 = Guid.NewGuid();
        var groupIds = new List<Guid> { groupId1, groupId2 };
        var groupResponse = new GroupResponse
        {
            Groups = new List<Group>
            {
                new() { Id = groupId1.ToString(), DisplayName = "Group 1" },
                new() { Id = groupId2.ToString(), DisplayName = "Group 2" }
            }
        };
        MockHttpMessageHandler handler = new(HttpStatusCode.OK, groupResponse);
        var httpClient = new HttpClient(handler);
        _httpClientFactory.CreateClient(Arg.Any<string>()).Returns(httpClient);

        // Act
        await _client.GetGroupsByObjectIdsAsync(groupIds);

        // Assert
        var capturedRequest = handler.CapturedRequests.First();
        using (Assert.EnterMultipleScope())
        {
            Assert.That(capturedRequest.Url, Does.Contain($"$filter=id in ('{groupId1}','{groupId2}')"));
            Assert.That(capturedRequest.Url, Does.Contain("$select=id,displayName"));
        }
    }

    [Test]
    public async Task GetGroupsByObjectIdsAsync_HandlesNullResponseGracefully()
    {
        // Arrange
        var batchSize = 15;
        var batchCount = 2;
        var groupsToRetrieveCount = batchSize * batchCount;
        var groupIds = Enumerable.Range(1, groupsToRetrieveCount).Select(_ => Guid.NewGuid()).ToList();

        int callCount = 0;
        var handler = new MockHttpMessageHandler((request) =>
          {
              callCount++;
              // First batch returns null, second batch returns valid response
              if (callCount == 1)
              {
                  return new HttpResponseMessage(HttpStatusCode.OK)
                  {
                      Content = JsonContent.Create<GroupResponse?>(null)
                  };
              }
              else
              {
                  var response = new GroupResponse
                  {
                      Groups = groupIds.Skip(batchSize).Take(batchSize).Select(id => new Group { Id = id.ToString(), DisplayName = $"Group {id}" }).ToList()
                  };
                  return new HttpResponseMessage(HttpStatusCode.OK)
                  {
                      Content = JsonContent.Create(response)
                  };
              }
          });

        var httpClient = new HttpClient(handler);
        _httpClientFactory.CreateClient(Arg.Any<string>()).Returns(httpClient);

        // Act
        var result = await _client.GetGroupsByObjectIdsAsync(groupIds);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result, Is.Not.Null);
            // Should only have groups from the second batch
            Assert.That(result.Groups, Has.Count.EqualTo(batchSize));
            Assert.That(handler.CapturedRequests, Has.Count.EqualTo(batchCount));
        }
    }

    [Test]
    public async Task GetUsersByGroupIdAsync_ReturnsUsers_WhenResponseIsSuccessful()
    {
        // Arrange
        var groupId = Guid.NewGuid();
        var expectedResponse = new UserResponse
        {
            Users = new List<User>
            {
                new() { OId = "1", DisplayName = "User1" },
                new() { OId = "2", DisplayName = "User2" }
            }
        };

        var httpClient = new HttpClient(new MockHttpMessageHandler(HttpStatusCode.OK, expectedResponse));
        _httpClientFactory.CreateClient(Arg.Any<string>()).Returns(httpClient);

        // Act
        var result = await _client.GetUsersByGroupIdAsync(groupId);

        // Assert
        Assert.That(result, Is.Not.Null);
        Assert.That(result.Users, Has.Count.EqualTo(expectedResponse.Users.Count));
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result.Users[0].OId, Is.EqualTo(expectedResponse.Users[0].OId));
            Assert.That(result.Users[0].DisplayName, Is.EqualTo(expectedResponse.Users[0].DisplayName));
            Assert.That(result.Users[1].OId, Is.EqualTo(expectedResponse.Users[1].OId));
            Assert.That(result.Users[1].DisplayName, Is.EqualTo(expectedResponse.Users[1].DisplayName));
        }
    }

    [Test]
    public async Task GetUsersByGroupIdAsync_ReturnsEmptyResponse_WhenNoUsers()
    {
        // Arrange
        var groupId = Guid.NewGuid();
        var userResponse = new UserResponse { Users = new List<User>() };
        var httpClient = new HttpClient(new MockHttpMessageHandler(HttpStatusCode.OK, userResponse));
        _httpClientFactory.CreateClient(Arg.Any<string>()).Returns(httpClient);

        // Act
        var result = await _client.GetUsersByGroupIdAsync(groupId);

        // Assert
        Assert.That(result.Users, Is.Empty);
    }

    [Test]
    public async Task GetUsersByGroupIdAsync_BuildsCorrectRequestUrl()
    {
        // Arrange
        var groupId = Guid.NewGuid();
        var userResponse = new UserResponse { Users = new List<User>() };
        MockHttpMessageHandler handler = new(HttpStatusCode.OK, userResponse);
        var httpClient = new HttpClient(handler);
        _httpClientFactory.CreateClient(Arg.Any<string>()).Returns(httpClient);

        // Act
        await _client.GetUsersByGroupIdAsync(groupId);

        // Assert
        var capturedRequest = handler.CapturedRequests.First();
        using (Assert.EnterMultipleScope())
        {
            Assert.That(capturedRequest.Method, Is.EqualTo(HttpMethod.Get));
            Assert.That(capturedRequest.Url, Does.Contain($"/groups/{groupId}/members"));
            Assert.That(capturedRequest.Url, Does.Contain("$select=displayName%2cid%2caccountEnabled"));
            Assert.That(capturedRequest.Url, Does.Contain("$top=999"));
        }
    }

    [Test]
    public async Task GetUsersByGroupIdAsync_IncludesContinuationToken_WhenProvided()
    {
        // Arrange
        var groupId = Guid.NewGuid();
        var continuationToken = "test-skip-token";
        var userResponse = new UserResponse { Users = new List<User>() };
        MockHttpMessageHandler handler = new(HttpStatusCode.OK, userResponse);
        var httpClient = new HttpClient(handler);
        _httpClientFactory.CreateClient(Arg.Any<string>()).Returns(httpClient);

        // Act
        await _client.GetUsersByGroupIdAsync(groupId, continuationToken);

        // Assert
        var capturedRequest = handler.CapturedRequests.First();
        Assert.That(capturedRequest.Url, Does.Contain($"$skiptoken={continuationToken}"));
    }

    [Test]
    public async Task GetUsersByGroupIdAsync_DoesNotIncludeContinuationToken_WhenNull()
    {
        // Arrange
        var groupId = Guid.NewGuid();
        var userResponse = new UserResponse { Users = new List<User>() };
        MockHttpMessageHandler handler = new(HttpStatusCode.OK, userResponse);
        var httpClient = new HttpClient(handler);
        _httpClientFactory.CreateClient(Arg.Any<string>()).Returns(httpClient);

        // Act
        await _client.GetUsersByGroupIdAsync(groupId, null);

        // Assert
        var capturedRequest = handler.CapturedRequests.First();
        Assert.That(capturedRequest.Url, Does.Not.Contain("$skiptoken"));
    }

    [Test]
    public async Task GetUsersByGroupIdAsync_DoesNotIncludeContinuationToken_WhenEmpty()
    {
        // Arrange
        var groupId = Guid.NewGuid();
        var userResponse = new UserResponse { Users = new List<User>() };
        MockHttpMessageHandler handler = new(HttpStatusCode.OK, userResponse);
        var httpClient = new HttpClient(handler);
        _httpClientFactory.CreateClient(Arg.Any<string>()).Returns(httpClient);

        // Act
        await _client.GetUsersByGroupIdAsync(groupId, string.Empty);

        // Assert
        var capturedRequest = handler.CapturedRequests.First();
        Assert.That(capturedRequest.Url, Does.Not.Contain("$skiptoken"));
    }

    [Test]
    public void GetUsersByGroupIdAsync_ThrowsException_WhenResponseIsUnsuccessful()
    {
        // Arrange
        var groupId = Guid.NewGuid();
        var httpClient = new HttpClient(new MockHttpMessageHandler(HttpStatusCode.BadRequest, "Error"));
        _httpClientFactory.CreateClient(Arg.Any<string>()).Returns(httpClient);

        // Act & Assert
        var ex = Assert.ThrowsAsync<HttpRequestException>(() => _client.GetUsersByGroupIdAsync(groupId));
        Assert.That(ex.Message, Does.Contain("Failed to retrieve users of a group"));
    }

    [Test]
    public void GetUsersByGroupIdAsync_ThrowsHttpRequestException_OnFailure()
    {
        // Arrange
        var groupId = Guid.NewGuid();
        var httpClient = new HttpClient(new MockHttpMessageHandler(HttpStatusCode.InternalServerError, ""));
        _httpClientFactory.CreateClient(Arg.Any<string>()).Returns(httpClient);

        // Act & Assert
        var ex = Assert.ThrowsAsync<HttpRequestException>(() => _client.GetUsersByGroupIdAsync(groupId));
        Assert.That(ex.Message, Does.Contain("Failed to retrieve users of a group"));
    }

    [Test]
    public async Task SearchGroupsByDisplayNameAsync_ReturnsGroups_WhenGroupsAreFound()
    {
        // Arrange
        var displayName = "Test";
        var expectedResponse = new GroupResponse
        {
            Groups = new List<Group>
            {
                new() { Id = Guid.NewGuid().ToString(), DisplayName = "Test Group 1" },
                new() { Id = Guid.NewGuid().ToString(), DisplayName = "Test Group 2" }
            }
        };
        var httpClient = new HttpClient(new MockHttpMessageHandler(HttpStatusCode.OK, expectedResponse));
        _httpClientFactory.CreateClient(Arg.Any<string>()).Returns(httpClient);

        // Act
        var result = await _client.SearchGroupsByDisplayNameAsync(displayName);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result, Is.Not.Null);
            Assert.That(result.Groups, Has.Count.EqualTo(expectedResponse.Groups.Count));
            Assert.That(result.Groups[0].Id, Is.EqualTo(expectedResponse.Groups[0].Id));
            Assert.That(result.Groups[0].DisplayName, Is.EqualTo(expectedResponse.Groups[0].DisplayName));
            Assert.That(result.Groups[1].Id, Is.EqualTo(expectedResponse.Groups[1].Id));
            Assert.That(result.Groups[1].DisplayName, Is.EqualTo(expectedResponse.Groups[1].DisplayName));
        }
    }

    [Test]
    public async Task SearchGroupsByDisplayNameAsync_ReturnsEmptyResponse_WhenNoGroupsFound()
    {
        // Arrange
        var displayName = "Nonexistent";
        var groupResponse = new GroupResponse { Groups = new List<Group>() };
        var httpClient = new HttpClient(new MockHttpMessageHandler(HttpStatusCode.OK, groupResponse));
        _httpClientFactory.CreateClient(Arg.Any<string>()).Returns(httpClient);

        // Act
        var result = await _client.SearchGroupsByDisplayNameAsync(displayName);

        // Assert
        Assert.That(result.Groups, Is.Empty);
    }

    [Test]
    public async Task SearchGroupsByDisplayNameAsync_EncodesQueryParameterCorrectly()
    {
        // Arrange
        var displayName = "Test Group";
        var groupResponse = new GroupResponse
        {
            Groups = new List<Group> { new() { Id = Guid.NewGuid().ToString(), DisplayName = "Test Group" } }
        };
        MockHttpMessageHandler handler = new(HttpStatusCode.OK, groupResponse);
        var httpClient = new HttpClient(handler);
        _httpClientFactory.CreateClient(Arg.Any<string>()).Returns(httpClient);

        // Act
        var result = await _client.SearchGroupsByDisplayNameAsync(displayName);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result, Is.Not.Null);
            Assert.That(result.Groups, Has.Count.EqualTo(1));
            Assert.That(result.Groups[0].DisplayName, Is.EqualTo("Test Group"));
            // Verify query encoding
            var expectedEncodedQuery = HttpUtility.UrlEncode($"\"displayName:{displayName}\"");
            Assert.That(handler.CapturedRequests.Any(req => req.Url.Contains(expectedEncodedQuery)), Is.True);
        }
    }

    [Test]
    public async Task SearchGroupsByDisplayNameAsync_EscapesBackslashes()
    {
        // Arrange
        var displayName = @"Test\Group";
        var groupResponse = new GroupResponse
        {
            Groups = new List<Group> { new() { Id = Guid.NewGuid().ToString(), DisplayName = displayName } }
        };
        MockHttpMessageHandler handler = new(HttpStatusCode.OK, groupResponse);
        var httpClient = new HttpClient(handler);
        _httpClientFactory.CreateClient(Arg.Any<string>()).Returns(httpClient);

        // Act
        var result = await _client.SearchGroupsByDisplayNameAsync(displayName);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result, Is.Not.Null);
            // Verify backslash was double-escaped (first to \\ then URL-encoded to %5c%5c)
            var capturedRequest = handler.CapturedRequests.First();
            Assert.That(capturedRequest.Url, Does.Contain("Test%5c%5cGroup"));
        }
    }

    [Test]
    public async Task SearchGroupsByDisplayNameAsync_EscapesQuotes()
    {
        // Arrange
        var displayName = "Test\"Group";
        var groupResponse = new GroupResponse
        {
            Groups = new List<Group> { new() { Id = Guid.NewGuid().ToString(), DisplayName = displayName } }
        };
        MockHttpMessageHandler handler = new(HttpStatusCode.OK, groupResponse);
        var httpClient = new HttpClient(handler);
        _httpClientFactory.CreateClient(Arg.Any<string>()).Returns(httpClient);

        // Act
        var result = await _client.SearchGroupsByDisplayNameAsync(displayName);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result, Is.Not.Null);
            // Verify quotes were escaped (\" becomes %5c%22 in URL encoding)
            var capturedRequest = handler.CapturedRequests.First();
            Assert.That(capturedRequest.Url, Does.Contain("Test%5c%22Group"));
        }
    }

    [Test]
    public async Task SearchGroupsByDisplayNameAsync_EscapesBackslashesAndQuotesTogether()
    {
        // Arrange
        var displayName = "AA\\BB\"CC";
        var expectedResponse = new GroupResponse
        {
            Groups = new()
        };
        var httpHandler = new MockHttpMessageHandler(HttpStatusCode.OK, expectedResponse);
        var httpClient = new HttpClient(httpHandler);
        _httpClientFactory.CreateClient(Arg.Any<string>()).Returns(httpClient);

        // Act
        _ = await _client.SearchGroupsByDisplayNameAsync(displayName);

        // Assert
        Assert.That(httpHandler.CapturedRequests.Single().Url, Does.EndWith("$search=%22displayName%3aAA%5c%5cBB%5c%22CC%22"));
    }

    [Test]
    public async Task SearchGroupsByDisplayNameAsync_IncludesContinuationToken_WhenProvided()
    {
        // Arrange
        var displayName = "Test";
        var continuationToken = "test-skip-token";
        var groupResponse = new GroupResponse { Groups = new List<Group>() };
        MockHttpMessageHandler handler = new(HttpStatusCode.OK, groupResponse);
        var httpClient = new HttpClient(handler);
        _httpClientFactory.CreateClient(Arg.Any<string>()).Returns(httpClient);

        // Act
        await _client.SearchGroupsByDisplayNameAsync(displayName, continuationToken);

        // Assert
        var capturedRequest = handler.CapturedRequests.First();
        Assert.That(capturedRequest.Url, Does.Contain($"$skiptoken={continuationToken}"));
    }

    [Test]
    public async Task SearchGroupsByDisplayNameAsync_DoesNotIncludeContinuationToken_WhenNull()
    {
        // Arrange
        var displayName = "Test";
        var groupResponse = new GroupResponse { Groups = new List<Group>() };
        MockHttpMessageHandler handler = new(HttpStatusCode.OK, groupResponse);
        var httpClient = new HttpClient(handler);
        _httpClientFactory.CreateClient(Arg.Any<string>()).Returns(httpClient);

        // Act
        await _client.SearchGroupsByDisplayNameAsync(displayName, null);

        // Assert
        var capturedRequest = handler.CapturedRequests.First();
        Assert.That(capturedRequest.Url, Does.Not.Contain("$skiptoken"));
    }

    [Test]
    public async Task SearchGroupsByDisplayNameAsync_DoesNotIncludeContinuationToken_WhenEmpty()
    {
        // Arrange
        var displayName = "Test";
        var groupResponse = new GroupResponse { Groups = new List<Group>() };
        MockHttpMessageHandler handler = new(HttpStatusCode.OK, groupResponse);
        var httpClient = new HttpClient(handler);
        _httpClientFactory.CreateClient(Arg.Any<string>()).Returns(httpClient);

        // Act
        await _client.SearchGroupsByDisplayNameAsync(displayName, string.Empty);

        // Assert
        var capturedRequest = handler.CapturedRequests.First();
        Assert.That(capturedRequest.Url, Does.Not.Contain("$skiptoken"));
    }

    [Test]
    public async Task SearchGroupsByDisplayNameAsync_AddsPreferModernSearchHeader()
    {
        // Arrange
        var displayName = "Test";
        var groupResponse = new GroupResponse
        {
            Groups = new List<Group> { new() { Id = Guid.NewGuid().ToString(), DisplayName = "Test Group" } }
        };
        MockHttpMessageHandler handler = new(HttpStatusCode.OK, groupResponse);
        var httpClient = new HttpClient(handler);
        _httpClientFactory.CreateClient(Arg.Any<string>()).Returns(httpClient);

        // Act
        await _client.SearchGroupsByDisplayNameAsync(displayName);

        // Assert
        var capturedRequest = handler.CapturedRequests.First();
        using (Assert.EnterMultipleScope())
        {
            Assert.That(capturedRequest.Headers.ContainsKey("Prefer"), Is.True);
            Assert.That(capturedRequest.Headers["Prefer"], Does.Contain("legacySearch=false"));
        }
    }

    [Test]
    public async Task SearchGroupsByDisplayNameAsync_BuildsCorrectRequestUrl()
    {
        // Arrange
        var displayName = "Test";
        var groupResponse = new GroupResponse { Groups = new List<Group>() };
        MockHttpMessageHandler handler = new(HttpStatusCode.OK, groupResponse);
        var httpClient = new HttpClient(handler);
        _httpClientFactory.CreateClient(Arg.Any<string>()).Returns(httpClient);

        // Act
        await _client.SearchGroupsByDisplayNameAsync(displayName);

        // Assert
        var capturedRequest = handler.CapturedRequests.First();
        using (Assert.EnterMultipleScope())
        {
            Assert.That(capturedRequest.Url, Does.Contain("/v1.0/groups"));
            Assert.That(capturedRequest.Url, Does.Contain("$search="));
        }
    }

    [Test]
    public async Task SearchGroupsByDisplayNameAsync_ReturnsEmptyResponse_WhenNullResponse()
    {
        // Arrange
        var displayName = "Test";
        var httpClient = new HttpClient(new MockHttpMessageHandler((request) =>
        {
            return new HttpResponseMessage(HttpStatusCode.OK)
            {
                Content = JsonContent.Create<GroupResponse?>(null)
            };
        }));
        _httpClientFactory.CreateClient(Arg.Any<string>()).Returns(httpClient);

        // Act
        var result = await _client.SearchGroupsByDisplayNameAsync(displayName);

        // Assert
        Assert.That(result.Groups, Is.Empty);
    }

    [Test]
    public void SearchGroupsByDisplayNameAsync_ThrowsException_WhenResponseIsUnsuccessful()
    {
        // Arrange
        var displayName = "test-group";
        var httpClient = new HttpClient(new MockHttpMessageHandler(HttpStatusCode.BadRequest, "Error"));
        _httpClientFactory.CreateClient(Arg.Any<string>()).Returns(httpClient);

        // Act & Assert
        Assert.ThrowsAsync<HttpRequestException>(() => _client.SearchGroupsByDisplayNameAsync(displayName));
    }
}
