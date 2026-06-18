using Microsoft.Extensions.Logging;

namespace IdentityServer.MicrosoftGraph.Tests;

[TestFixture]
public class MicrosoftGraphApiClientBaseTests
{
    #region BuildResourceRelativePath Tests

    [Test]
    public void BuildResourceRelativePath_WithResourceOnly_ReturnsCorrectPath()
    {
        // Arrange
        var resource = "users";

        // Act
        var result = TestableApiClient.BuildResourceRelativePathPublic(resource, null, null);

        // Assert
        Assert.That(result, Is.EqualTo("/v1.0/users"));
    }

    [Test]
    public void BuildResourceRelativePath_WithResourceSelectAndFilter_ReturnsPathWithBothParameters()
    {
        // Arrange
        var resource = "applications";
        var select = "id,appId";
        var filter = "appId eq 'test-app-id'";

        // Act
        var result = TestableApiClient.BuildResourceRelativePathPublic(resource, select, filter);

        // Assert
        Assert.That(result, Is.EqualTo("/v1.0/applications?$select=id%2cappId&$filter=appId+eq+%27test-app-id%27"));
    }

    [Test]
    public void BuildResourceRelativePath_WithEmptySelect_ReturnsPathWithoutSelectParameter()
    {
        // Arrange
        var resource = "users";
        var select = string.Empty;

        // Act
        var result = TestableApiClient.BuildResourceRelativePathPublic(resource, select, null);

        // Assert
        Assert.That(result, Is.EqualTo("/v1.0/users"));
    }

    [Test]
    public void BuildResourceRelativePath_WithEmptyFilter_ReturnsPathWithoutFilterParameter()
    {
        // Arrange
        var resource = "groups";
        var filter = string.Empty;

        // Act
        var result = TestableApiClient.BuildResourceRelativePathPublic(resource, null, filter);

        // Assert
        Assert.That(result, Is.EqualTo("/v1.0/groups"));
    }

    #endregion

    #region BuildItemRelativePath Tests

    [Test]
    public void BuildItemRelativePath_WithResourceAndIdOnly_ReturnsCorrectPath()
    {
        // Arrange
        var resource = "users";
        var id = "user-id-123";

        // Act
        var result = TestableApiClient.BuildItemRelativePathPublic(resource, id, null, null);

        // Assert
        Assert.That(result, Is.EqualTo("/v1.0/users/user-id-123"));
    }

    [Test]
    public void BuildItemRelativePath_WithAllParameters_ReturnsPathWithAllQueryParameters()
    {
        // Arrange
        var resource = "users";
        var id = "user-id-123";
        var select = "id,displayName,accountEnabled";
        var filter = "accountEnabled eq true";

        // Act
        var result = TestableApiClient.BuildItemRelativePathPublic(resource, id, select, filter);

        // Assert
        Assert.That(result, Is.EqualTo("/v1.0/users/user-id-123?$select=id%2cdisplayName%2caccountEnabled&$filter=accountEnabled+eq+true"));
    }

    [Test]
    public void BuildItemRelativePath_WithEmptySelectAndFilter_ReturnsPathWithoutQueryParameters()
    {
        // Arrange
        var resource = "groups";
        var id = "group-id-456";

        // Act
        var result = TestableApiClient.BuildItemRelativePathPublic(resource, id, string.Empty, string.Empty);

        // Assert
        Assert.That(result, Is.EqualTo("/v1.0/groups/group-id-456"));
    }

    #endregion

    #region Test Helper Class

    /// <summary>
    /// Testable wrapper for MicrosoftGraphApiClientBase that exposes protected/private methods for testing.
    /// </summary>
    private class TestableApiClient : MicrosoftGraphApiClientBase
    {
        protected override string ClientName => "TestClient";

        public TestableApiClient(IHttpClientFactory clientFactory, ILogger logger)
            : base(clientFactory, logger)
        {
        }

        // Public wrappers to test protected/private static methods
        public static string BuildResourceRelativePathPublic(string resource, string? select, string? filter)
            => BuildResourceRelativePath(resource, select, filter);

        public static string BuildItemRelativePathPublic(string resource, string id, string? select, string? filter)
            => BuildItemRelativePath(resource, id, select, filter);
    }

    #endregion
}
