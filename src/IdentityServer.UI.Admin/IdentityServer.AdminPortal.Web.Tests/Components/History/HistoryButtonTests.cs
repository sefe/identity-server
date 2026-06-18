using Bunit;
using Microsoft.AspNetCore.Components;
using Microsoft.Extensions.DependencyInjection;
using Telerik.Blazor.Components;
using IdentityServer.AdminPortal.Web.Components.History;

namespace IdentityServer.AdminPortal.Web.Tests.Components.History;

public class HistoryButtonTests
{
    private Bunit.TestContext _ctx = default!;
    private FakeNavigationManager _navigationManager = default!;

    [SetUp]
    public void Setup()
    {
        _ctx = new Bunit.TestContext();
        _ctx.JSInterop.Mode = JSRuntimeMode.Loose;
        _navigationManager = new FakeNavigationManager();
        _ctx.Services.AddSingleton<NavigationManager>(_navigationManager);
    }

    [TearDown]
    public void TearDown()
    {
        _ctx?.Dispose();
    }

    [Test]
    public void Component_WithApplicationId_RendersButtonWithDefaultText()
    {
        // Arrange & Act
        var cut = _ctx.RenderComponent<TelerikRootComponent>(parameters => parameters
            .AddChildContent<HistoryButton>(childParameters => childParameters
                .Add(p => p.ApplicationId, 123)));

        // Assert
        var button = cut.FindComponent<TelerikButton>();
        Assert.That(button.Instance.ChildContent, Is.Not.Null);
    }

    [Test]
    public void Component_WithCustomButtonText_DisplaysCustomText()
    {
        // Arrange & Act
        var cut = _ctx.RenderComponent<TelerikRootComponent>(parameters => parameters
            .AddChildContent<HistoryButton>(childParameters => childParameters
                .Add(p => p.ApplicationId, 123)
                .Add(p => p.ButtonText, "View History")));

        // Assert
        var button = cut.Find("button");
        Assert.That(button.TextContent, Does.Contain("View History"));
    }

    [Test]
    public void Component_WithDefaultSize_UsesSmallSize()
    {
        // Arrange & Act
        var cut = _ctx.RenderComponent<TelerikRootComponent>(parameters => parameters
            .AddChildContent<HistoryButton>(childParameters => childParameters
                .Add(p => p.ApplicationId, 123)));

        // Assert
        var button = cut.FindComponent<TelerikButton>();
        Assert.That(button.Instance.Size, Is.EqualTo("small"));
    }

    [Test]
    public void Component_WithCustomSize_UsesCustomSize()
    {
        // Arrange & Act
        var cut = _ctx.RenderComponent<TelerikRootComponent>(parameters => parameters
            .AddChildContent<HistoryButton>(childParameters => childParameters
                .Add(p => p.ApplicationId, 123)
                .Add(p => p.Size, "medium")));

        // Assert
        var button = cut.FindComponent<TelerikButton>();
        Assert.That(button.Instance.Size, Is.EqualTo("medium"));
    }

    [Test]
    public void NavigateToHistory_WithApplicationId_NavigatesToCorrectUrl()
    {
        // Arrange
        var cut = _ctx.RenderComponent<TelerikRootComponent>(parameters => parameters
            .AddChildContent<HistoryButton>(childParameters => childParameters
                .Add(p => p.ApplicationId, 42)));

        // Act
        var button = cut.Find("button");
        button.Click();

        // Assert
        Assert.That(_navigationManager.LastNavigatedUri, Is.EqualTo("/applications/42/history"));
    }

    [Test]
    public void NavigateToHistory_WithApiResourceId_NavigatesToCorrectUrl()
    {
        // Arrange
        var cut = _ctx.RenderComponent<TelerikRootComponent>(parameters => parameters
            .AddChildContent<HistoryButton>(childParameters => childParameters
                .Add(p => p.ApiResourceId, 99)));

        // Act
        var button = cut.Find("button");
        button.Click();

        // Assert
        Assert.That(_navigationManager.LastNavigatedUri, Is.EqualTo("/apiresources/99/history"));
    }

    [Test]
    public void NavigateToHistory_WithSystemPermissionId_NavigatesToCorrectUrl()
    {
        // Arrange
        var cut = _ctx.RenderComponent<TelerikRootComponent>(parameters => parameters
            .AddChildContent<HistoryButton>(childParameters => childParameters
                .Add(p => p.SystemPermissionId, 7)));

        // Act
        var button = cut.Find("button");
        button.Click();

        // Assert
        Assert.That(_navigationManager.LastNavigatedUri, Is.EqualTo("/systempermissions/7/history"));
    }

    [Test]
    public void NavigateToHistory_WithApplicationIdAndEntityTypeFilter_AppendsQueryString()
    {
        // Arrange
        var cut = _ctx.RenderComponent<TelerikRootComponent>(parameters => parameters
            .AddChildContent<HistoryButton>(childParameters => childParameters
                .Add(p => p.ApplicationId, 10)
                .Add(p => p.EntityTypeFilter, "Role")));

        // Act
        var button = cut.Find("button");
        button.Click();

        // Assert
        Assert.That(_navigationManager.LastNavigatedUri, Is.EqualTo("/applications/10/history?entityType=Role"));
    }

    [Test]
    public void NavigateToHistory_WithApplicationIdAndEntityIdFilter_AppendsQueryString()
    {
        // Arrange
        var cut = _ctx.RenderComponent<TelerikRootComponent>(parameters => parameters
            .AddChildContent<HistoryButton>(childParameters => childParameters
                .Add(p => p.ApplicationId, 10)
                .Add(p => p.EntityIdFilter, "entity-123")));

        // Act
        var button = cut.Find("button");
        button.Click();

        // Assert
        Assert.That(_navigationManager.LastNavigatedUri, Is.EqualTo("/applications/10/history?entityId=entity-123"));
    }

    [Test]
    public void NavigateToHistory_WithApplicationIdAndBothFilters_AppendsBothQueryStrings()
    {
        // Arrange
        var cut = _ctx.RenderComponent<TelerikRootComponent>(parameters => parameters
            .AddChildContent<HistoryButton>(childParameters => childParameters
                .Add(p => p.ApplicationId, 10)
                .Add(p => p.EntityTypeFilter, "Role")
                .Add(p => p.EntityIdFilter, "entity-123")));

        // Act
        var button = cut.Find("button");
        button.Click();

        // Assert
        Assert.That(_navigationManager.LastNavigatedUri, Is.EqualTo("/applications/10/history?entityType=Role&entityId=entity-123"));
    }

    [Test]
    public void NavigateToHistory_WithApiResourceIdAndBothFilters_AppendsBothQueryStrings()
    {
        // Arrange
        var cut = _ctx.RenderComponent<TelerikRootComponent>(parameters => parameters
            .AddChildContent<HistoryButton>(childParameters => childParameters
                .Add(p => p.ApiResourceId, 5)
                .Add(p => p.EntityTypeFilter, "Scope")
                .Add(p => p.EntityIdFilter, "scope-456")));

        // Act
        var button = cut.Find("button");
        button.Click();

        // Assert
        Assert.That(_navigationManager.LastNavigatedUri, Is.EqualTo("/apiresources/5/history?entityType=Scope&entityId=scope-456"));
    }

    [Test]
    public void NavigateToHistory_WithSystemPermissionIdAndBothFilters_AppendsBothQueryStrings()
    {
        // Arrange
        var cut = _ctx.RenderComponent<TelerikRootComponent>(parameters => parameters
            .AddChildContent<HistoryButton>(childParameters => childParameters
                .Add(p => p.SystemPermissionId, 3)
                .Add(p => p.EntityTypeFilter, "Permission")
                .Add(p => p.EntityIdFilter, "perm-789")));

        // Act
        var button = cut.Find("button");
        button.Click();

        // Assert
        Assert.That(_navigationManager.LastNavigatedUri, Is.EqualTo("/systempermissions/3/history?entityType=Permission&entityId=perm-789"));
    }

    [Test]
    public void NavigateToHistory_WithSpecialCharactersInEntityTypeFilter_EscapesQueryString()
    {
        // Arrange
        var cut = _ctx.RenderComponent<TelerikRootComponent>(parameters => parameters
            .AddChildContent<HistoryButton>(childParameters => childParameters
                .Add(p => p.ApplicationId, 10)
                .Add(p => p.EntityTypeFilter, "Role & Permission")));

        // Act
        var button = cut.Find("button");
        button.Click();

        // Assert
        Assert.That(_navigationManager.LastNavigatedUri, Does.Contain("Role%20%26%20Permission"));
    }

    [Test]
    public void NavigateToHistory_WithSpecialCharactersInEntityIdFilter_EscapesQueryString()
    {
        // Arrange
        var cut = _ctx.RenderComponent<TelerikRootComponent>(parameters => parameters
            .AddChildContent<HistoryButton>(childParameters => childParameters
                .Add(p => p.ApplicationId, 10)
                .Add(p => p.EntityIdFilter, "entity/with/slashes")));

        // Act
        var button = cut.Find("button");
        button.Click();

        // Assert
        Assert.That(_navigationManager.LastNavigatedUri, Does.Contain("entity%2Fwith%2Fslashes"));
    }

    [Test]
    public void NavigateToHistory_WithNoIdParameters_DoesNotNavigate()
    {
        // Arrange
        var initialUri = _navigationManager.LastNavigatedUri;
        var cut = _ctx.RenderComponent<TelerikRootComponent>(parameters => parameters
            .AddChildContent<HistoryButton>());

        // Act
        var button = cut.Find("button");
        button.Click();

        // Assert
        Assert.That(_navigationManager.LastNavigatedUri, Is.EqualTo(initialUri));
    }

    [Test]
    public void NavigateToHistory_WithMultipleIds_UsesFirstNonNullId()
    {
        // Arrange - ApplicationId should take precedence
        var cut = _ctx.RenderComponent<TelerikRootComponent>(parameters => parameters
            .AddChildContent<HistoryButton>(childParameters => childParameters
                .Add(p => p.ApplicationId, 1)
                .Add(p => p.ApiResourceId, 2)
                .Add(p => p.SystemPermissionId, 3)));

        // Act
        var button = cut.Find("button");
        button.Click();

        // Assert
        Assert.That(_navigationManager.LastNavigatedUri, Is.EqualTo("/applications/1/history"));
    }

    [Test]
    public void NavigateToHistory_WithOnlyApiResourceIdSet_UsesApiResourceRoute()
    {
        // Arrange
        var cut = _ctx.RenderComponent<TelerikRootComponent>(parameters => parameters
            .AddChildContent<HistoryButton>(childParameters => childParameters
                .Add(p => p.ApiResourceId, 2)
                .Add(p => p.SystemPermissionId, 3)));

        // Act
        var button = cut.Find("button");
        button.Click();

        // Assert
        Assert.That(_navigationManager.LastNavigatedUri, Is.EqualTo("/apiresources/2/history"));
    }

    [Test]
    public void NavigateToHistory_WithEmptyEntityTypeFilter_DoesNotAppendEntityType()
    {
        // Arrange
        var cut = _ctx.RenderComponent<TelerikRootComponent>(parameters => parameters
            .AddChildContent<HistoryButton>(childParameters => childParameters
                .Add(p => p.ApplicationId, 10)
                .Add(p => p.EntityTypeFilter, string.Empty)
                .Add(p => p.EntityIdFilter, "entity-123")));

        // Act
        var button = cut.Find("button");
        button.Click();

        // Assert
        Assert.That(_navigationManager.LastNavigatedUri, Is.EqualTo("/applications/10/history?entityId=entity-123"));
    }

    [Test]
    public void NavigateToHistory_WithEmptyEntityIdFilter_DoesNotAppendEntityId()
    {
        // Arrange
        var cut = _ctx.RenderComponent<TelerikRootComponent>(parameters => parameters
            .AddChildContent<HistoryButton>(childParameters => childParameters
                .Add(p => p.ApplicationId, 10)
                .Add(p => p.EntityTypeFilter, "Role")
                .Add(p => p.EntityIdFilter, string.Empty)));

        // Act
        var button = cut.Find("button");
        button.Click();

        // Assert
        Assert.That(_navigationManager.LastNavigatedUri, Is.EqualTo("/applications/10/history?entityType=Role"));
    }

    private class FakeNavigationManager : NavigationManager
    {
        public string LastNavigatedUri { get; private set; }

        public FakeNavigationManager()
        {
            Initialize("http://localhost/", "http://localhost/");
            LastNavigatedUri = string.Empty;
        }

        protected override void NavigateToCore(string uri, bool forceLoad)
        {
            var absoluteUri = ToAbsoluteUri(uri);
            LastNavigatedUri = absoluteUri.PathAndQuery;
        }
    }
}
