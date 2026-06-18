using NSubstitute;
using IdentityServer.Abstraction.Entities.EntraEntities;
using IdentityServer.MicrosoftGraph;

namespace IdentityServer.Data.Test.Services;

[TestFixture]
public class EntraApplicationServiceTests
{
    private IMicrosoftGraphApplicationApi _graphAppApi;
    private EntraApplicationService _service;

    [SetUp]
    public void SetUp()
    {
        _graphAppApi = Substitute.For<IMicrosoftGraphApplicationApi>();
        _service = new EntraApplicationService(_graphAppApi);
    }

    [Test]
    public async Task GetByIdAsync_ReturnsApplication_WhenApplicationExists()
    {
        // Arrange
        var appId = "test-app-id-123";
        var expectedApplication = new Application
        {
            Id = "object-id-456",
            AppId = appId,
            DisplayName = "Test Application"
        };

        _graphAppApi.GetApplicationByAppIdAsync(appId).Returns(expectedApplication);

        // Act
        var result = await _service.GetByIdAsync(appId);

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
    public async Task GetByIdAsync_ReturnsNull_WhenApplicationDoesNotExist()
    {
        // Arrange
        var appId = "non-existent-app-id";
        _graphAppApi.GetApplicationByAppIdAsync(appId).Returns((Application)null);

        // Act
        var result = await _service.GetByIdAsync(appId);

        // Assert
        Assert.That(result, Is.Null);
    }

    [Test]
    public async Task GetByIdAsync_CallsGraphApiWithCorrectParameter()
    {
        // Arrange
        var appId = "test-app-id";
        var expectedApplication = new Application
        {
            Id = "object-id",
            AppId = appId,
            DisplayName = "Test App"
        };

        _graphAppApi.GetApplicationByAppIdAsync(appId).Returns(expectedApplication);

        // Act
        await _service.GetByIdAsync(appId);

        // Assert
        await _graphAppApi.Received(1).GetApplicationByAppIdAsync(appId);
    }

    [Test]
    public async Task GetByIdAsync_PassesThroughGraphApiResult()
    {
        // Arrange
        var appId = "app-123";
        var application = new Application
        {
            Id = "obj-123",
            AppId = appId,
            DisplayName = "Sample Application"
        };

        _graphAppApi.GetApplicationByAppIdAsync(appId).Returns(application);

        // Act
        var result = await _service.GetByIdAsync(appId);

        // Assert
        Assert.That(result, Is.SameAs(application));
    }

    [Test]
    public void GetByIdAsync_ThrowsException_WhenGraphApiThrows()
    {
        // Arrange
        var appId = "test-app-id";
        var expectedException = new HttpRequestException("Graph API error");
        _graphAppApi.GetApplicationByAppIdAsync(appId).Returns(Task.FromException<Application>(expectedException));

        // Act & Assert
        var ex = Assert.ThrowsAsync<HttpRequestException>(() => _service.GetByIdAsync(appId));
        Assert.That(ex, Is.SameAs(expectedException));
    }

    [Test]
    public async Task GetByIdAsync_HandlesEmptyDisplayName()
    {
        // Arrange
        var appId = "app-with-empty-name";
        var application = new Application
        {
            Id = "object-id",
            AppId = appId,
            DisplayName = string.Empty
        };

        _graphAppApi.GetApplicationByAppIdAsync(appId).Returns(application);

        // Act
        var result = await _service.GetByIdAsync(appId);

        // Assert
        Assert.That(result, Is.Not.Null);
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result.AppId, Is.EqualTo(appId));
            Assert.That(result.DisplayName, Is.Empty);
        }
    }

    [Test]
    public async Task GetByIdAsync_HandlesSpecialCharactersInAppId()
    {
        // Arrange
        var appId = "app-id-with-special-chars-!@#$%";
        var application = new Application
        {
            Id = "object-id",
            AppId = appId,
            DisplayName = "Special App"
        };

        _graphAppApi.GetApplicationByAppIdAsync(appId).Returns(application);

        // Act
        var result = await _service.GetByIdAsync(appId);

        // Assert
        Assert.That(result, Is.Not.Null);
        Assert.That(result.AppId, Is.EqualTo(appId));
    }

    [Test]
    public async Task GetByIdAsync_CalledMultipleTimes_CallsGraphApiEachTime()
    {
        // Arrange
        var appId = "test-app-id";
        var application = new Application
        {
            Id = "object-id",
            AppId = appId,
            DisplayName = "Test App"
        };

        _graphAppApi.GetApplicationByAppIdAsync(appId).Returns(application);

        // Act
        await _service.GetByIdAsync(appId);
        await _service.GetByIdAsync(appId);
        await _service.GetByIdAsync(appId);

        // Assert
        await _graphAppApi.Received(3).GetApplicationByAppIdAsync(appId);
    }

    [Test]
    public async Task GetByIdAsync_WithDifferentAppIds_CallsGraphApiWithCorrectParameters()
    {
        // Arrange
        var appId1 = "app-id-1";
        var appId2 = "app-id-2";
        var application1 = new Application
        {
            Id = "object-id-1",
            AppId = appId1,
            DisplayName = "App 1"
        };
        var application2 = new Application
        {
            Id = "object-id-2",
            AppId = appId2,
            DisplayName = "App 2"
        };

        _graphAppApi.GetApplicationByAppIdAsync(appId1).Returns(application1);
        _graphAppApi.GetApplicationByAppIdAsync(appId2).Returns(application2);

        // Act
        var result1 = await _service.GetByIdAsync(appId1);
        var result2 = await _service.GetByIdAsync(appId2);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result1, Is.Not.Null);
            Assert.That(result1.AppId, Is.EqualTo(appId1));
            Assert.That(result2, Is.Not.Null);
            Assert.That(result2.AppId, Is.EqualTo(appId2));
        }

        await _graphAppApi.Received(1).GetApplicationByAppIdAsync(appId1);
        await _graphAppApi.Received(1).GetApplicationByAppIdAsync(appId2);
    }
}
