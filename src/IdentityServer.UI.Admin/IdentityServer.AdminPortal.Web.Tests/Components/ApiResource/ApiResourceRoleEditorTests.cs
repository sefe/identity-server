using Bunit;
using Microsoft.AspNetCore.Components;
using Microsoft.AspNetCore.Components.Rendering;
using IdentityServer.Abstraction.DTO.ApiResources;
using IdentityServer.AdminPortal.Web.Components.ApiResource;

namespace IdentityServer.AdminPortal.Web.Tests.Components.ApiResource;

[TestFixture]
public class ApiResourceRoleEditorTests : Bunit.TestContext
{
    private const string _expectedOffcanvasClass = "offcanvas";
    private const string _expectedBackdropClass = "offcanvas-backdrop";

    private readonly ApiResourceDtoRead _apiResource = new()
    {
        Id = 1,
        Name = "TestApiResource",
        DisplayName = "Test API Resource",
        Enabled = true,
        Roles = new List<ApiResourcePropertyRoleDtoRead>()
    };

    [Test]
    public void Component_WithApiResource_InitializesCorrectly()
    {
        // Arrange & Act
        var component = RenderComponent<ApiResourceRoleEditor>(parameters => parameters
            .Add(p => p.ApiResource, _apiResource));

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(component.Instance, Is.Not.Null);
            Assert.That(component.Instance.ApiResource, Is.EqualTo(_apiResource));
        }
    }

    [Test]
    public void Component_WhenClosed_DoesNotRenderOffcanvas()
    {
        // Arrange & Act
        var component = RenderComponent<ApiResourceRoleEditor>(parameters => parameters
            .Add(p => p.ApiResource, _apiResource));

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(component.FindAll($".{_expectedOffcanvasClass}"), Is.Empty);
            Assert.That(component.FindAll($".{_expectedBackdropClass}"), Is.Empty);
        }
    }

    [Test]
    public async Task Component_WhenOpen_RendersOffcanvas()
    {
        // Arrange
        ComponentFactories.AddStub<ApiResourceRoleInfoNew>();
        var component = RenderComponent<ApiResourceRoleEditor>(parameters => parameters
            .Add(p => p.ApiResource, _apiResource));

        // Act
        await OpenDrawerAsync(component);

        // Assert
        var offcanvasHeader = component.Find(".offcanvas-header");
        var backdrop = component.Find(".offcanvas-body");
        backdrop.MarkupMatches("<div diff:ignoreAttributes></div>");
    }

    [Test]
    public async Task Component_WhenOpen_RendersTitle()
    {
        // Arrange
        ComponentFactories.AddStub<ApiResourceRoleInfoNew>();
        var component = RenderComponent<ApiResourceRoleEditor>(parameters => parameters
            .Add(p => p.ApiResource, _apiResource));

        // Act
        await OpenDrawerAsync(component);

        // Assert
        var offcanvasHeader = component.Find(".offcanvas-header");
        offcanvasHeader.MarkupMatches("<div diff:ignoreAttributes><h5 class=\"offcanvas-title\" id=\"roleEditorTitle\">New API Role</h5></div>");

    }

    [Test]
    public async Task CloseEditorDrawer_ClosesDrawer()
    {
        // Arrange
        ComponentFactories.AddStub<ApiResourceRoleInfoNew>();
        var component = RenderComponent<ApiResourceRoleEditor>(parameters => parameters
            .Add(p => p.ApiResource, _apiResource));

        await OpenDrawerAsync(component);
        Assert.That(component.FindAll($".{_expectedOffcanvasClass}"), Is.Not.Empty);

        // Act
        await CloseDrawerAsync(component);

        // Assert
        Assert.That(component.FindAll($".{_expectedOffcanvasClass}"), Is.Empty);
    }

    [Test]
    public async Task OnSave_WhenReadonly_DoesNotInvokeCallback()
    {
        // Arrange
        var callbackInvoked = false;
        ComponentFactories.Add<ApiResourceRoleInfoNew, StubApiResourceRoleInfoNew>();
        var component = RenderComponent<ApiResourceRoleEditor>(parameters => parameters
            .Add(p => p.ApiResource, _apiResource)
            .Add(p => p.OnApiResourceUpdate, () => { callbackInvoked = true; return Task.CompletedTask; })
            .Add(p => p.IsReadonly, true));

        await OpenDrawerAsync(component);
        Assert.That(component.FindAll($".{_expectedOffcanvasClass}"), Is.Not.Empty);

        // Act - Trigger OnSave through child component's event
        var stubChild = component.FindComponent<StubApiResourceRoleInfoNew>();
        await component.InvokeAsync(stubChild.Instance.OnSave.InvokeAsync);

        // Assert
        Assert.That(callbackInvoked, Is.False);
    }

    [Test]
    public async Task OnSave_WhenNotReadonly_InvokesCallbackAndClosesDrawer()
    {
        // Arrange
        var callbackInvoked = false;
        ComponentFactories.Add<ApiResourceRoleInfoNew, StubApiResourceRoleInfoNew>();

        var component = RenderComponent<ApiResourceRoleEditor>(parameters => parameters
            .Add(p => p.ApiResource, _apiResource)
            .Add(p => p.OnApiResourceUpdate, () => { callbackInvoked = true; return Task.CompletedTask; }));

        // open drawer
        await OpenDrawerAsync(component);
        Assert.That(component.FindAll($".{_expectedOffcanvasClass}"), Is.Not.Empty);

        // Act - Find the stub child component and trigger its OnSave event manually
        var stubChild = component.FindComponent<StubApiResourceRoleInfoNew>();
        await component.InvokeAsync(stubChild.Instance.OnSave.InvokeAsync);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(callbackInvoked, Is.True);
            Assert.That(component.FindAll($".{_expectedOffcanvasClass}"), Is.Empty, "Drawer should be closed after save");
        }
    }

    [Test]
    public async Task OnCancel_ClosesDrawerWithoutInvokingCallback()
    {
        // Arrange
        var callbackInvoked = false;
        ComponentFactories.Add<ApiResourceRoleInfoNew, StubApiResourceRoleInfoNew>();

        var component = RenderComponent<ApiResourceRoleEditor>(parameters => parameters
            .Add(p => p.ApiResource, _apiResource)
            .Add(p => p.OnApiResourceUpdate, () => { callbackInvoked = true; return Task.CompletedTask; }));

        await OpenDrawerAsync(component);

        // Act - Find the stub child component and trigger its OnCancel event manually
        var stubChild = component.FindComponent<StubApiResourceRoleInfoNew>();
        await component.InvokeAsync(stubChild.Instance.OnCancel.InvokeAsync);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(callbackInvoked, Is.False, "Callback should not be invoked on cancel");
            Assert.That(component.FindAll($".{_expectedOffcanvasClass}"), Is.Empty, "Drawer should be closed after cancel");
        }
    }

    private static async Task OpenDrawerAsync(IRenderedComponent<ApiResourceRoleEditor> component)
    {
        await component.InvokeAsync(() =>
        {
            component.Instance.OpenDrawerForNewRole();
            component.Render();
        });
    }

    private static async Task CloseDrawerAsync(IRenderedComponent<ApiResourceRoleEditor> component)
    {
        await component.InvokeAsync(() =>
        {
            component.Instance.CloseEditorDrawer();
            component.Render();
        });
    }
}

public class StubApiResourceRoleInfoNew : ComponentBase
{
    [Parameter] public ApiResourceDtoRead ApiResource { get; set; } = default!;
    [Parameter] public EventCallback OnSave { get; set; }
    [Parameter] public EventCallback OnCancel { get; set; }

    protected override void BuildRenderTree(RenderTreeBuilder builder)
    {
        builder.OpenElement(0, "div");
        builder.AddAttribute(1, "class", "stub-child-component");
        builder.AddContent(2, $"Stub ApiResourceRoleInfoNew for ApiResource: {ApiResource?.Name}");
        builder.CloseElement();
    }
}
