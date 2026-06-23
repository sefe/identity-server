// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

using NSubstitute;
using IdentityServer.Abstraction.Configs;
using IdentityServer.Abstraction.Contracts;
using IdentityServer.Abstraction.Contracts.MicrosoftGraph;
using IdentityServer.Abstraction.Entities.EntraEntities;
using IdentityServer.MicrosoftGraph.Caching;

namespace IdentityServer.MicrosoftGraph.Tests.Caching;

[TestFixture]
public class EntraApplicationCachedServiceTests
{
    private IEntraApplicationService _mockInnerService;
    private ICache<Application> _mockCache;
    private IMicrosoftEntraCacheConfig _mockCacheConfig;
    private EntraApplicationCachedService _service;

    [SetUp]
    public void SetUp()
    {
        _mockInnerService = Substitute.For<IEntraApplicationService>();
        _mockCache = Substitute.For<ICache<Application>>();
        _mockCacheConfig = Substitute.For<IMicrosoftEntraCacheConfig>();

        // Default cache expiration setup
        _mockCacheConfig.ApplicationExpiration.Returns(TimeSpan.FromMinutes(30));

        _service = new EntraApplicationCachedService(_mockInnerService, _mockCache, _mockCacheConfig);
    }

    [Test]
    public async Task GetByIdAsync_WithCachedApplication_ReturnsFromCache()
    {
        // Arrange
        var cachedApp = new Application
        {
            Id = "id-123",
            AppId = "app-123",
            DisplayName = "Cached Application"
        };

        _mockCache.GetOrAddAsync(
                    cachedApp.AppId,
                    Arg.Any<TimeSpan>(),
                    Arg.Any<Func<Task<Application>>>())
                .Returns(cachedApp);

        // Act
        var result = await _service.GetByIdAsync(cachedApp.AppId);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result, Is.Not.Null);
            Assert.That(result!.Id, Is.EqualTo(cachedApp.Id));
            Assert.That(result.AppId, Is.EqualTo(cachedApp.AppId));
            Assert.That(result.DisplayName, Is.EqualTo(cachedApp.DisplayName));
        }

        await _mockCache.Received(1).GetOrAddAsync(
                cachedApp.AppId,
                _mockCacheConfig.ApplicationExpiration,
                Arg.Any<Func<Task<Application>>>());
    }

    [Test]
    public async Task GetByIdAsync_WithNonCachedApplication_FetchesFromInnerService()
    {
        // Arrange
        var application = new Application
        {
            Id = "id-456",
            AppId = "app-456",
            DisplayName = "New Application"
        };

        _mockInnerService.GetByIdAsync(application.AppId).Returns(application);

        _mockCache.GetOrAddAsync(
            application.AppId,
                    Arg.Any<TimeSpan>(),
                    Arg.Any<Func<Task<Application>>>())
                .Returns(callInfo =>
                    {
                        var factory = callInfo.ArgAt<Func<Task<Application>>>(2);
                        return factory();
                    });

        // Act
        var result = await _service.GetByIdAsync(application.AppId);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result, Is.Not.Null);
            Assert.That(result!.Id, Is.EqualTo("id-456"));
            Assert.That(result.AppId, Is.EqualTo(application.AppId));
            Assert.That(result.DisplayName, Is.EqualTo("New Application"));
        }

        await _mockInnerService.Received(1).GetByIdAsync(application.AppId);
        await _mockCache.Received(1).GetOrAddAsync(
                application.AppId,
                _mockCacheConfig.ApplicationExpiration,
                Arg.Any<Func<Task<Application>>>());
    }

    [Test]
    public async Task GetByIdAsync_WithNullResult_ReturnsNull()
    {
        // Arrange
        var appId = "non-existent-app";

        _mockInnerService.GetByIdAsync(appId).Returns((Application?)null);

        _mockCache.GetOrAddAsync(
                appId,
                Arg.Any<TimeSpan>(),
                Arg.Any<Func<Task<Application>>>())
            .Returns(callInfo =>
                 {
                     var factory = callInfo.ArgAt<Func<Task<Application>>>(2);
                     return factory();
                 });

        // Act
        var result = await _service.GetByIdAsync(appId);

        // Assert
        Assert.That(result, Is.Null);

        await _mockInnerService.Received(1).GetByIdAsync(appId);
        await _mockCache.Received(1).GetOrAddAsync(
                appId,
                _mockCacheConfig.ApplicationExpiration,
                Arg.Any<Func<Task<Application>>>());
    }

    [Test]
    public async Task GetByIdAsync_UsesCorrectCacheExpiration()
    {
        // Arrange
        var customExpiration = TimeSpan.FromHours(2);
        _mockCacheConfig.ApplicationExpiration.Returns(customExpiration);

        var application = new Application
        {
            Id = "id-789",
            AppId = "app-789",
            DisplayName = "Test Application"
        };

        _mockInnerService.GetByIdAsync(application.AppId).Returns(application);

        _mockCache.GetOrAddAsync(
                application.AppId,
                Arg.Any<TimeSpan>(),
                Arg.Any<Func<Task<Application>>>())
            .Returns(callInfo =>
            {
                var factory = callInfo.ArgAt<Func<Task<Application>>>(2);
                return factory();
            });

        // Act
        await _service.GetByIdAsync(application.AppId);

        // Assert
        await _mockCache.Received(1).GetOrAddAsync(
                application.AppId,
                customExpiration,
                Arg.Any<Func<Task<Application>>>());
    }

    [Test]
    public async Task GetByIdAsync_WithDifferentAppIds_UsesDifferentCacheKeys()
    {
        // Arrange
        var appId1 = "app-001";
        var appId2 = "app-002";

        var application1 = new Application
        {
            Id = "id-001",
            AppId = appId1,
            DisplayName = "Application 1"
        };

        var application2 = new Application
        {
            Id = "id-002",
            AppId = appId2,
            DisplayName = "Application 2"
        };

        _mockInnerService.GetByIdAsync(appId1).Returns(application1);
        _mockInnerService.GetByIdAsync(appId2).Returns(application2);

        _mockCache.GetOrAddAsync(
                Arg.Any<string>(),
                Arg.Any<TimeSpan>(),
                Arg.Any<Func<Task<Application>>>())
            .Returns(callInfo =>
            {
                var factory = callInfo.ArgAt<Func<Task<Application>>>(2);
                return factory();
            });

        // Act
        await _service.GetByIdAsync(appId1);
        await _service.GetByIdAsync(appId2);

        // Assert
        await _mockCache.Received(1).GetOrAddAsync(
                appId1,
                Arg.Any<TimeSpan>(),
                Arg.Any<Func<Task<Application>>>());

        await _mockCache.Received(1).GetOrAddAsync(
                appId2,
                Arg.Any<TimeSpan>(),
                Arg.Any<Func<Task<Application>>>());
    }
}
