using Duende.IdentityServer.Models;
using Duende.IdentityServer.Stores;
using Duende.IdentityServer.Validation;
using Microsoft.Extensions.Logging;
using NSubstitute;
using IdentityServer.Services.Validation;
using IdentityServer.Tests.Common;

namespace IdentityServer.Test.Services.Validation;

[TestFixture]
public class ApiResourceIsEnabledValidatorTests
{
    private IResourceStore _resourceStore;
    private IScopeParser _scopeParser;
    private MockLogger<ApiResourceIsEnabledValidator> _logger;
    private TestableApiResourceIsEnabledValidator _sut;

    // Testable subclass to expose protected method
    public class TestableApiResourceIsEnabledValidator : ApiResourceIsEnabledValidator
    {
        public TestableApiResourceIsEnabledValidator(IResourceStore store, IScopeParser scopeParser, ILogger<ApiResourceIsEnabledValidator> logger)
            : base(store, scopeParser, logger) { }
        public Task CallValidateScopeAsync(Client client, Resources resourcesFromStore, ParsedScopeValue requestedScope, ResourceValidationResult result)
            => ValidateScopeAsync(client, resourcesFromStore, requestedScope, result);
    }

    [SetUp]
    public void SetUp()
    {
        _resourceStore = Substitute.For<IResourceStore>();
        _scopeParser = Substitute.For<IScopeParser>();
        _logger = new MockLogger<ApiResourceIsEnabledValidator>();
        _sut = new TestableApiResourceIsEnabledValidator(_resourceStore, _scopeParser, _logger);
    }

    [Test]
    public async Task ValidateApiResourceIsEnabled_ScopeNameWithoutDot_DoesNothing()
    {
        // Arrange
        var result = new ResourceValidationResult();
        var scopeName = "openid";

        // Act
        await _sut.ValidateApiResourceIsEnabled(scopeName, result);

        // Assert
        Assert.That(result.InvalidScopes, Is.Empty);
    }

    [Test]
    public async Task ValidateApiResourceIsEnabled_ScopeNameWithEmptyApiName_DoesNothing()
    {
        // Arrange
        var result = new ResourceValidationResult();
        var scopeName = ".scope";

        // Act
        await _sut.ValidateApiResourceIsEnabled(scopeName, result);

        // Assert
        Assert.That(result.InvalidScopes, Is.Empty);
    }

    [Test]
    public async Task ValidateApiResourceIsEnabled_ApiResourceNotFound_AddsInvalidScope()
    {
        // Arrange
        var result = new ResourceValidationResult();
        var scopeName = "api1.scope";
        _resourceStore.FindApiResourcesByNameAsync(Arg.Any<IEnumerable<string>>())
            .Returns(Enumerable.Empty<ApiResource>());

        // Act
        await _sut.ValidateApiResourceIsEnabled(scopeName, result);

        // Assert
        Assert.That(result.InvalidScopes, Has.One.EqualTo(scopeName));
    }

    [Test]
    public async Task ValidateApiResourceIsEnabled_MultipleApiResourcesFound_AddsInvalidScope()
    {
        // Arrange
        var result = new ResourceValidationResult();
        var scopeName = "api1.scope";
        var apiResources = new[] { new ApiResource("api1"), new ApiResource("api1") };
        _resourceStore.FindApiResourcesByNameAsync(Arg.Any<IEnumerable<string>>())
            .Returns(apiResources);

        // Act
        await _sut.ValidateApiResourceIsEnabled(scopeName, result);

        // Assert
        Assert.That(result.InvalidScopes, Has.One.EqualTo(scopeName));
    }

    [Test]
    public async Task ValidateApiResourceIsEnabled_ApiResourceDisabled_AddsInvalidScope()
    {
        // Arrange
        var result = new ResourceValidationResult();
        var scopeName = "api1.scope";
        var apiResource = new ApiResource("api1") { Enabled = false };
        _resourceStore.FindApiResourcesByNameAsync(Arg.Any<IEnumerable<string>>())
            .Returns(new[] { apiResource });

        // Act
        await _sut.ValidateApiResourceIsEnabled(scopeName, result);

        // Assert
        Assert.That(result.InvalidScopes, Has.One.EqualTo(scopeName));
    }

    [Test]
    public async Task ValidateApiResourceIsEnabled_ApiResourceEnabled_DoesNothing()
    {
        // Arrange
        var result = new ResourceValidationResult();
        var scopeName = "api1.scope";
        var apiResource = new ApiResource("api1") { Enabled = true };
        _resourceStore.FindApiResourcesByNameAsync(Arg.Any<IEnumerable<string>>())
            .Returns(new[] { apiResource });

        // Act
        await _sut.ValidateApiResourceIsEnabled(scopeName, result);

        // Assert
        Assert.That(result.InvalidScopes, Is.Empty);
    }

    [Test]
    public async Task ValidateScopeAsync_WhenBaseValidationFails_DoesNotCallValidateApiResourceIsEnabled()
    {
        // Arrange
        var client = new Client(); // client is not granted the requested scope and will fail the base validation
        var apiResources = new List<ApiResource> { new("api1") { Enabled = true }, new("api1") { Enabled = true } }; // 2 API Resources with the same name}
        var resources = new Resources()
        {
            ApiResources = apiResources,
            ApiScopes = [new ApiScope { Name = "api1.scope", Enabled = true }],
        };
        _resourceStore.FindApiResourcesByNameAsync(Arg.Any<IEnumerable<string>>()).Returns(apiResources);
        var requestedScope = new ParsedScopeValue("api1.scope");
        var result = new ResourceValidationResult();

        // Act
        await _sut.CallValidateScopeAsync(client, resources, requestedScope, result);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result.InvalidScopes, Has.One.EqualTo("api1.scope"));
            Assert.That(_logger.CapturedErrors, Has.Count.EqualTo(1));
            Assert.That(_logger.CapturedErrors[0], Does.Contain("is not allowed access to scope api1.scope")); // error logged by the base validation
        }
    }

    [Test]
    public async Task ValidateScopeAsync_WhenBaseValidationSucceeds_CallsValidateApiResourceIsEnabled()
    {
        // Arrange
        var client = new Client() { AllowedScopes = ["api1.scope"] };
        var apiResources = new List<ApiResource> { new("api1") { Enabled = true } };
        var resources = new Resources()
        {
            ApiResources = apiResources,
            ApiScopes = [new ApiScope { Name = "api1.scope", Enabled = true }],
        };
        _resourceStore.FindApiResourcesByNameAsync(Arg.Any<IEnumerable<string>>()).Returns(apiResources);
        var requestedScope = new ParsedScopeValue("api1.scope");
        var result = new ResourceValidationResult();

        // Act
        await _sut.CallValidateScopeAsync(client, resources, requestedScope, result);

        // Assert
        Assert.That(result.InvalidScopes, Is.Empty);
    }
}
