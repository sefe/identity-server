using AngleSharp.Dom;
using Bunit;
using Microsoft.AspNetCore.Components;
using Microsoft.Extensions.DependencyInjection;
using NSubstitute;
using Telerik.Blazor.Components;
using IdentityServer.Abstraction.DTO.Clients;
using IdentityServer.AdminPortal.Web.Components.ClientAppRegistration;
using IdentityServer.AdminPortal.Web.Components.Interop;
using IdentityServer.AdminPortal.Web.Services;
using IdentityServer.Tests.Common;
using TestContext = Bunit.TestContext;

namespace IdentityServer.AdminPortal.Web.Tests.Components.ClientAppRegistration;

[TestFixture]
public class ClientPostLogoutRedirectUriListTests
{
    private TestContext _ctx;
    private IAdminApiService _adminApiService;
    private NotificationService _mockNotificationService;
    private IConfirmationService _mockConfirmationService;
    private MockHttpMessageHandler _mockHandler;
    private HttpClient _mockHttpClient;

    [SetUp]
    public void Setup()
    {
        _ctx = new TestContext();
        SetupCommonInterop(_ctx);

        // Setup AdminApiService with mock HTTP handler
        _mockHandler = new MockHttpMessageHandler(System.Net.HttpStatusCode.OK, "{}");
        _mockHttpClient = new HttpClient(_mockHandler)
        {
            BaseAddress = new Uri("https://localhost/")
        };

        var mockHttpClientFactory = Substitute.For<IHttpClientFactory>();
        mockHttpClientFactory.CreateClient(AdminApiService.HttpClientName).Returns(_mockHttpClient);
        _adminApiService = new AdminApiService(mockHttpClientFactory);

        _mockNotificationService = Substitute.For<NotificationService>();
        _mockConfirmationService = Substitute.For<IConfirmationService>();

        _ctx.Services.AddSingleton(_adminApiService);
        _ctx.Services.AddSingleton(_mockNotificationService);
        _ctx.Services.AddSingleton(_mockConfirmationService);
        _ctx.Services.AddSingleton(Substitute.For<IClipboardService>());
        _ctx.Services.AddTelerikBlazor();
    }

    [TearDown]
    public void TearDown()
    {
        _ctx.Dispose();
        _mockHttpClient?.Dispose();
        _mockHandler?.Dispose();
    }

    [Test]
    public void Render_WithNoPostLogoutRedirectUris_ShowsNoneMessage()
    {
        // Arrange
        var client = CreateTestClient();

        // Act
        var cut = _ctx.RenderComponent<TelerikRootComponent>(parameters => parameters
            .AddChildContent<ClientPostLogoutRedirectUriList>(childParameters => childParameters
                .Add(p => p.Application, client)
                .Add(p => p.IsReadonly, false)
                .Add(p => p.OnApplicationUpdate, EventCallback.Factory.Create(this, () => { }))
            )
        );

        // Assert
        var noneMessage = cut.Find("span.form-control-plaintext");
        Assert.That(noneMessage.TextContent, Is.EqualTo("None"));
    }

    [Test]
    public void Render_WithPostLogoutRedirectUris_ShowsUrisInList()
    {
        // Arrange
        var client = CreateTestClient();
        client.PostLogoutRedirectUris.Add(new ClientPropertyPostLogoutRedirectUriDtoRead
        {
            Id = 1,
            ClientId = client.Id,
            PostLogoutRedirectUri = "https://example.com/logout"
        });
        client.PostLogoutRedirectUris.Add(new ClientPropertyPostLogoutRedirectUriDtoRead
        {
            Id = 2,
            ClientId = client.Id,
            PostLogoutRedirectUri = "http://localhost:3000/signout"
        });

        // Act
        var cut = _ctx.RenderComponent<TelerikRootComponent>(parameters => parameters
            .AddChildContent<ClientPostLogoutRedirectUriList>(childParameters => childParameters
                .Add(p => p.Application, client)
                .Add(p => p.IsReadonly, false)
                .Add(p => p.OnApplicationUpdate, EventCallback.Factory.Create(this, () => { }))
            )
        );

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(cut.Markup, Does.Contain("https://example.com/logout"));
            Assert.That(cut.Markup, Does.Contain("http://localhost:3000/signout"));
        }
    }

    [Test]
    public void Render_WhenNotReadonly_ShowsAddNewButton()
    {
        // Arrange
        var client = CreateTestClient();

        // Act
        var cut = _ctx.RenderComponent<TelerikRootComponent>(parameters => parameters
            .AddChildContent<ClientPostLogoutRedirectUriList>(childParameters => childParameters
                .Add(p => p.Application, client)
                .Add(p => p.IsReadonly, false)
                .Add(p => p.OnApplicationUpdate, EventCallback.Factory.Create(this, () => { }))
            )
        );

        // Assert
        var addButton = cut.Find("button.k-button-solid-primary");
        Assert.That(addButton.TextContent, Does.Contain("Add New"));
    }

    [Test]
    public void Render_WhenReadonly_DoesNotShowAddNewButton()
    {
        // Arrange
        var client = CreateTestClient();

        // Act
        var cut = _ctx.RenderComponent<TelerikRootComponent>(parameters => parameters
            .AddChildContent<ClientPostLogoutRedirectUriList>(childParameters => childParameters
                .Add(p => p.Application, client)
                .Add(p => p.IsReadonly, true)
                .Add(p => p.OnApplicationUpdate, EventCallback.Factory.Create(this, () => { }))
            )
        );

        // Assert
        var buttons = cut.FindAll("button");
        var addButtons = buttons.Where(b => b.TextContent.Contains("Add New"));
        Assert.That(addButtons, Is.Empty);
    }

    [Test]
    public void Render_WhenReadonly_DoesNotShowDeleteButtons()
    {
        // Arrange
        var client = CreateTestClient();
        client.PostLogoutRedirectUris.Add(new ClientPropertyPostLogoutRedirectUriDtoRead
        {
            Id = 1,
            ClientId = client.Id,
            PostLogoutRedirectUri = "https://example.com/logout"
        });

        // Act
        var cut = _ctx.RenderComponent<TelerikRootComponent>(parameters => parameters
            .AddChildContent<ClientPostLogoutRedirectUriList>(childParameters => childParameters
                .Add(p => p.Application, client)
                .Add(p => p.IsReadonly, true)
                .Add(p => p.OnApplicationUpdate, EventCallback.Factory.Create(this, () => { }))
            )
        );

        // Assert
        var deleteButtons = cut.FindAll("button").Where(b => b.ClassList.Contains("k-button-outline-error"));
        Assert.That(deleteButtons, Is.Empty);
    }

    [Test]
    public void Render_WhenNotReadonly_ShowsDeleteButtonPerUri()
    {
        // Arrange
        var client = CreateTestClient();
        client.PostLogoutRedirectUris.Add(new ClientPropertyPostLogoutRedirectUriDtoRead
        {
            Id = 1,
            ClientId = client.Id,
            PostLogoutRedirectUri = "https://example.com/logout"
        });
        client.PostLogoutRedirectUris.Add(new ClientPropertyPostLogoutRedirectUriDtoRead
        {
            Id = 2,
            ClientId = client.Id,
            PostLogoutRedirectUri = "https://example.com/logout-2"
        });

        // Act
        var cut = _ctx.RenderComponent<TelerikRootComponent>(parameters => parameters
            .AddChildContent<ClientPostLogoutRedirectUriList>(childParameters => childParameters
                .Add(p => p.Application, client)
                .Add(p => p.IsReadonly, false)
                .Add(p => p.OnApplicationUpdate, EventCallback.Factory.Create(this, () => { }))
            )
        );

        // Assert
        var addButtons = cut.FindAll("span.k-button-icon.k-svg-i-trash");
        Assert.That(addButtons, Has.Count.EqualTo(2));
    }

    [Test]
    public void AddNewButton_WhenClicked_ShowsAddForm()
    {
        // Arrange
        var client = CreateTestClient();

        var cut = _ctx.RenderComponent<TelerikRootComponent>(parameters => parameters
            .AddChildContent<ClientPostLogoutRedirectUriList>(childParameters => childParameters
                .Add(p => p.Application, client)
                .Add(p => p.IsReadonly, false)
                .Add(p => p.OnApplicationUpdate, EventCallback.Factory.Create(this, () => { }))
            )
        );

        // Act
        var addButton = cut.FindAll("button").First(b => b.TextContent.Contains("Add New"));
        addButton.Click();

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(cut.Markup, Does.Contain("Enter new Post-Logout Redirect URI here"));
            Assert.That(cut.FindAll("button").Any(b => b.TextContent.Contains("Add") && !b.TextContent.Contains("Add New")), Is.True);
            Assert.That(cut.FindAll("button").Any(b => b.TextContent.Contains("Cancel")), Is.True);
        }
    }

    [Test]
    public void CancelButton_WhenClicked_HidesAddForm()
    {
        // Arrange
        var client = CreateTestClient();

        var cut = _ctx.RenderComponent<TelerikRootComponent>(parameters => parameters
            .AddChildContent<ClientPostLogoutRedirectUriList>(childParameters => childParameters
                .Add(p => p.Application, client)
                .Add(p => p.IsReadonly, false)
                .Add(p => p.OnApplicationUpdate, EventCallback.Factory.Create(this, () => { }))
            )
        );

        // Show add form first
        var addButton = cut.FindAll("button").First(b => b.TextContent.Contains("Add New"));
        addButton.Click();

        // Act
        var cancelButton = cut.FindAll("button").First(b => b.TextContent.Contains("Cancel"));
        cancelButton.Click();

        // Assert
        Assert.That(cut.Markup, Does.Not.Contain("Enter new Post-Logout Redirect URI here"));
    }

    [Test]
    public void Render_WithValidHttpsUri_ShowsLiteralBadge()
    {
        // Arrange
        var client = CreateTestClient();
        client.PostLogoutRedirectUris.Add(new ClientPropertyPostLogoutRedirectUriDtoRead
        {
            Id = 1,
            ClientId = client.Id,
            PostLogoutRedirectUri = "https://example.com/logout"
        });

        // Act
        var cut = _ctx.RenderComponent<TelerikRootComponent>(parameters => parameters
            .AddChildContent<ClientPostLogoutRedirectUriList>(childParameters => childParameters
                .Add(p => p.Application, client)
                .Add(p => p.IsReadonly, false)
                .Add(p => p.OnApplicationUpdate, EventCallback.Factory.Create(this, () => { }))
            )
        );

        // Assert
        var literalBadge = cut.Find("span.badge.bg-secondary");
        Assert.That(literalBadge.TextContent, Is.EqualTo("Literal"));
    }

    [Test]
    public void Render_WithInsecureNonLoopbackUri_ShowsInsecureBadge()
    {
        // Arrange
        var client = CreateTestClient();
        client.PostLogoutRedirectUris.Add(new ClientPropertyPostLogoutRedirectUriDtoRead
        {
            Id = 1,
            ClientId = client.Id,
            PostLogoutRedirectUri = "http://example.com/logout"
        });

        // Act
        var cut = _ctx.RenderComponent<TelerikRootComponent>(parameters => parameters
            .AddChildContent<ClientPostLogoutRedirectUriList>(childParameters => childParameters
                .Add(p => p.Application, client)
                .Add(p => p.IsReadonly, false)
                .Add(p => p.OnApplicationUpdate, EventCallback.Factory.Create(this, () => { }))
            )
        );

        // Assert
        var insecureBadge = cut.Find("span.badge.bg-warning");
        Assert.That(insecureBadge.TextContent, Is.EqualTo("Insecure"));
    }

    [Test]
    public void Render_WithLoopbackUri_ShowsAnyPortBadge()
    {
        // Arrange
        var client = CreateTestClient();
        client.PostLogoutRedirectUris.Add(new ClientPropertyPostLogoutRedirectUriDtoRead
        {
            Id = 1,
            ClientId = client.Id,
            PostLogoutRedirectUri = "http://localhost/logout"
        });

        // Act
        var cut = _ctx.RenderComponent<TelerikRootComponent>(parameters => parameters
            .AddChildContent<ClientPostLogoutRedirectUriList>(childParameters => childParameters
                .Add(p => p.Application, client)
                .Add(p => p.IsReadonly, false)
                .Add(p => p.OnApplicationUpdate, EventCallback.Factory.Create(this, () => { }))
            )
        );

        // Assert
        var anyPortBadge = cut.Find("span.badge.bg-success");
        Assert.That(anyPortBadge.TextContent, Is.EqualTo("Any Port"));
    }

    [Test]
    public void Render_WithInvalidUri_ShowsInvalidBadge()
    {
        // Arrange
        var client = CreateTestClient();
        client.PostLogoutRedirectUris.Add(new ClientPropertyPostLogoutRedirectUriDtoRead
        {
            Id = 1,
            ClientId = client.Id,
            PostLogoutRedirectUri = "not-a-valid-uri"
        });

        // Act
        var cut = _ctx.RenderComponent<TelerikRootComponent>(parameters => parameters
            .AddChildContent<ClientPostLogoutRedirectUriList>(childParameters => childParameters
                .Add(p => p.Application, client)
                .Add(p => p.IsReadonly, false)
                .Add(p => p.OnApplicationUpdate, EventCallback.Factory.Create(this, () => { }))
            )
        );

        // Assert
        using (Assert.EnterMultipleScope())
        {
            var invalidBadge = cut.Find("span.badge.bg-danger");
            Assert.That(invalidBadge.TextContent, Is.EqualTo("Invalid"));

            var rowElement = cut.Find("div.border-danger");
            Assert.That(rowElement, Is.Not.Null, "Row should have danger border for invalid URI");
        }
    }

    [Test]
    public void Render_WithNonHttpSchemeUri_ShowsNonHttpBadge()
    {
        // Arrange
        var client = CreateTestClient();
        client.PostLogoutRedirectUris.Add(new ClientPropertyPostLogoutRedirectUriDtoRead
        {
            Id = 1,
            ClientId = client.Id,
            PostLogoutRedirectUri = "app://logout"
        });

        // Act
        var cut = _ctx.RenderComponent<TelerikRootComponent>(parameters => parameters
            .AddChildContent<ClientPostLogoutRedirectUriList>(childParameters => childParameters
                .Add(p => p.Application, client)
                .Add(p => p.IsReadonly, false)
                .Add(p => p.OnApplicationUpdate, EventCallback.Factory.Create(this, () => { }))
            )
        );

        // Assert
        var nonHttpBadge = cut.FindAll("span.badge.bg-warning").First(b => b.TextContent.Contains("Non-HTTP"));
        Assert.That(nonHttpBadge.TextContent, Is.EqualTo("Non-HTTP(S)"));
    }

    [Test]
    public void Render_WithPostLogoutRedirectUris_IncludesCopyToClipboardButton()
    {
        // Arrange
        var client = CreateTestClient();
        client.PostLogoutRedirectUris.Add(new ClientPropertyPostLogoutRedirectUriDtoRead
        {
            Id = 1,
            ClientId = client.Id,
            PostLogoutRedirectUri = "https://example.com/logout"
        });

        // Act
        var cut = _ctx.RenderComponent<TelerikRootComponent>(parameters => parameters
            .AddChildContent<ClientPostLogoutRedirectUriList>(childParameters => childParameters
                .Add(p => p.Application, client)
                .Add(p => p.IsReadonly, false)
                .Add(p => p.OnApplicationUpdate, EventCallback.Factory.Create(this, () => { }))
            )
        );

        // Assert
        Assert.That(cut.Markup, Does.Contain("Copy to clipboard"));
    }

    [Test]
    public void DeleteButton_WhenClicked_ShowsConfirmationDialog()
    {
        // Arrange
        var client = CreateTestClient();
        client.PostLogoutRedirectUris.Add(new ClientPropertyPostLogoutRedirectUriDtoRead
        {
            Id = 1,
            ClientId = client.Id,
            PostLogoutRedirectUri = "https://example.com/logout"
        });

        _mockConfirmationService.ConfirmAsync(
            Arg.Any<string>(),
            Arg.Any<string>(),
            Arg.Any<bool>())
            .Returns(Task.FromResult(false));

        var cut = _ctx.RenderComponent<TelerikRootComponent>(parameters => parameters
            .AddChildContent<ClientPostLogoutRedirectUriList>(childParameters => childParameters
                .Add(p => p.Application, client)
                .Add(p => p.IsReadonly, false)
                .Add(p => p.OnApplicationUpdate, EventCallback.Factory.Create(this, () => { }))
            )
        );

        // Act
        var deleteButton = cut.Find("button.k-button-outline-error");
        deleteButton.Click();

        // Assert
        _mockConfirmationService.Received(1).ConfirmAsync(
            "Delete Confirmation",
            Arg.Is<string>(s => s.Contains("https://example.com/logout")),
            Arg.Any<bool>());
    }

    [Test]
    public void DeleteButton_WhenConfirmed_CallsApiAndRemovesUri()
    {
        // Arrange
        var client = CreateTestClient();
        var uriToDelete = new ClientPropertyPostLogoutRedirectUriDtoRead
        {
            Id = 1,
            ClientId = client.Id,
            PostLogoutRedirectUri = "https://example.com/logout"
        };
        client.PostLogoutRedirectUris.Add(uriToDelete);

        _mockConfirmationService.ConfirmAsync(
            Arg.Any<string>(),
            Arg.Any<string>(),
            Arg.Any<bool>())
            .Returns(Task.FromResult(true));

        _mockHandler.SetResponse(System.Net.HttpStatusCode.OK, "1");

        var updateCallbackInvoked = false;
        var cut = _ctx.RenderComponent<TelerikRootComponent>(parameters => parameters
            .AddChildContent<ClientPostLogoutRedirectUriList>(childParameters => childParameters
                .Add(p => p.Application, client)
                .Add(p => p.IsReadonly, false)
                .Add(p => p.OnApplicationUpdate, EventCallback.Factory.Create(this, () => { updateCallbackInvoked = true; }))
            )
        );

        // Act
        var deleteButton = cut.Find("button.k-button-outline-error");
        deleteButton.Click();

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(client.PostLogoutRedirectUris, Is.Empty);
            Assert.That(updateCallbackInvoked, Is.True);
        }
    }

    [Test]
    public void DeleteButton_WhenCancelled_DoesNotRemoveUri()
    {
        // Arrange
        var client = CreateTestClient();
        var uriToDelete = new ClientPropertyPostLogoutRedirectUriDtoRead
        {
            Id = 1,
            ClientId = client.Id,
            PostLogoutRedirectUri = "https://example.com/logout"
        };
        client.PostLogoutRedirectUris.Add(uriToDelete);

        _mockConfirmationService.ConfirmAsync(
            Arg.Any<string>(),
            Arg.Any<string>(),
            Arg.Any<bool>())
            .Returns(Task.FromResult(false));

        var cut = _ctx.RenderComponent<TelerikRootComponent>(parameters => parameters
            .AddChildContent<ClientPostLogoutRedirectUriList>(childParameters => childParameters
                .Add(p => p.Application, client)
                .Add(p => p.IsReadonly, false)
                .Add(p => p.OnApplicationUpdate, EventCallback.Factory.Create(this, () => { }))
            )
        );

        // Act
        var deleteButton = cut.Find("button.k-button-outline-error");
        deleteButton.Click();

        // Assert
        Assert.That(client.PostLogoutRedirectUris, Does.Contain(uriToDelete));
    }

    private static void SetupCommonInterop(TestContext ctx)
    {
        ctx.JSInterop.SetupVoid("TelerikBlazor.setOptions", _ => true);
        ctx.JSInterop.SetupVoid("TelerikBlazor.initFilterMenu", _ => true);
        ctx.JSInterop.SetupVoid("TelerikBlazor.Form.initForm", _ => true);
        ctx.JSInterop.SetupVoid("TelerikBlazor.ToolBar.initializeToolBar", _ => true);
        ctx.JSInterop.Setup<string>("TelerikBlazor.getTimezoneOffset", _ => true).SetResult("0");
        ctx.JSInterop.Setup<string>("TelerikBlazor.getTimezone", _ => true).SetResult("UTC");
        ctx.JSInterop.SetupVoid("TelerikBlazor.initColumnResizable", _ => true);
        ctx.JSInterop.Setup<object>("TelerikBlazor.getElementBounds", _ => true).SetResult(new { width = 100, height = 100 });

        // Setup for copy to clipboard functionality
        ctx.JSInterop.SetupVoid("copyToClipboard", _ => true);
    }

    private static ClientDtoRead CreateTestClient()
    {
        return new ClientDtoRead
        {
            Id = 1,
            ClientId = "test-client",
            ClientName = "Test Client",
            Enabled = true,
            PostLogoutRedirectUris = new List<ClientPropertyPostLogoutRedirectUriDtoRead>()
        };
    }
}
