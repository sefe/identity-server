// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

using Bunit;
using Microsoft.AspNetCore.Components;
using Microsoft.Extensions.DependencyInjection;
using NSubstitute;
using IdentityServer.AdminPortal.Web.Components.ClientAppRegistration;
using IdentityServer.AdminPortal.Web.Services.Storage;
using IdentityServer.Abstraction.Entities.IdentityServerConfig;
using IdentityServer.AdminPortal.Web.Models;
using IdentityServer.Abstraction.DTO.Clients;
using Telerik.Blazor.Components;
using NSubstitute.ExceptionExtensions;
using TestContext = Bunit.TestContext;

namespace IdentityServer.AdminPortal.Web.Tests.Components.ClientAppRegistration;

[TestFixture]
public class ClientRoleMapListItemTests
{
    private TestContext _ctx;
    private IJSStorageService _mockStorageService;

    [SetUp]
    public void Setup()
    {
        _ctx = new TestContext();
        SetupCommonInterop(_ctx);
        _mockStorageService = Substitute.For<IJSStorageService>();
        _ctx.Services.AddSingleton(_mockStorageService);
        _ctx.Services.AddTelerikBlazor();
    }

    [TearDown]
    public void TearDown()
    {
        _ctx.Dispose();
    }

    [TestCase(RoleMapType.UserObjectId)]
    [TestCase(RoleMapType.SecurityGroup)]
    public void OnInitializedAsync_WithPageSizeStorageKey_RestoresCachedPageSize(RoleMapType roleMapType)
    {
        // Arrange
        int cachedPageSize = 50;
        string expectedStorageKey = $"idp.admin.client.rolemap.{roleMapType}.pagesize.gs";
        _mockStorageService.GetItem<int?>(Arg.Any<string>()).Returns(cachedPageSize);

        // Act
        var cut = _ctx.RenderComponent<TelerikRootComponent>(parameters => parameters
            .AddChildContent<ClientRoleMapListItem>(childParameters => childParameters
                .Add(p => p.MapType, roleMapType)
                .Add(p => p.MappedRoles, CreateMappedRoles(roleMapType))
                .Add(p => p.OnCreateNew, EventCallback.Factory.Create(this, () => { }))
                .Add(p => p.OnDeleteRoleMapping, EventCallback.Factory.Create<ClientPropertyRoleMappingDtoRead>(this, _ => { }))
            )
        );

        // Assert
        var pagingSection = cut.Find(".k-pager-sizes");
        var pageSizeSpan = cut.Find(".k-input-value-text");
        pageSizeSpan.MarkupMatches("<span class=\"k-input-value-text\">50</span>");
        _mockStorageService.Received(1).GetItem<int?>(expectedStorageKey);
    }

    [TestCase(RoleMapType.UserObjectId, "User")]
    [TestCase(RoleMapType.SecurityGroup, "Group")]
    public void Render_WithRoleMappingsAndNotReadonly_RendersCreateButton(RoleMapType roleMapType, string friendlyName)
    {
        // Arrange
        _mockStorageService.GetItem<int?>(Arg.Any<string>()).Returns(10);

        // Act
        var cut = _ctx.RenderComponent<TelerikRootComponent>(parameters => parameters
            .AddChildContent<ClientRoleMapListItem>(childParameters => childParameters
                .Add(p => p.MapType, roleMapType)
                .Add(p => p.IsReadonly, false)
                .Add(p => p.MappedRoles, CreateMappedRoles(roleMapType))
                .Add(p => p.OnCreateNew, EventCallback.Factory.Create(this, () => { }))
                .Add(p => p.OnDeleteRoleMapping, EventCallback.Factory.Create<ClientPropertyRoleMappingDtoRead>(this, _ => { }))
            )
        );

        // Assert
        var button = cut.Find(".k-button-text");
        using (Assert.EnterMultipleScope())
        {
            Assert.That(button.TextContent, Is.EqualTo($"Create {friendlyName} Mapping"));
            Assert.That(cut.Markup, Does.Contain(@$"<h5 class=""my-0"">{friendlyName} Role Mapping</h5>"));
        }
    }

    [TestCase(RoleMapType.UserObjectId, "User")]
    [TestCase(RoleMapType.SecurityGroup, "Group")]
    public void Render_WhenReadonly_DoesnotRenderCreateButton(RoleMapType roleMapType, string friendlyName)
    {
        // Arrange
        _mockStorageService.GetItem<int?>(Arg.Any<string>()).Returns(10);

        // Act
        var cut = _ctx.RenderComponent<TelerikRootComponent>(parameters => parameters
            .AddChildContent<ClientRoleMapListItem>(childParameters => childParameters
                .Add(p => p.MapType, roleMapType)
                .Add(p => p.IsReadonly, true)
                .Add(p => p.MappedRoles, CreateMappedRoles(roleMapType))
                .Add(p => p.OnCreateNew, EventCallback.Factory.Create(this, () => { }))
                .Add(p => p.OnDeleteRoleMapping, EventCallback.Factory.Create<ClientPropertyRoleMappingDtoRead>(this, _ => { }))
            )
        );

        // Assert
        Assert.That(cut.Markup, Does.Not.Contain($"Create {friendlyName} Mapping"));
        var buttons = cut.FindAll("button");
        var createButtons = buttons.Where(b => b.TextContent.Contains("Create"));
        Assert.That(createButtons, Is.Empty);
    }

    [Test]
    public void Component_WhenCreateButtonClicked_InvokesOnCreateNew()
    {
        // Arrange
        var createNewCalled = false;
        var cut = _ctx.RenderComponent<TelerikRootComponent>(parameters => parameters
            .AddChildContent<ClientRoleMapListItem>(childParameters => childParameters
            .Add(p => p.MapType, RoleMapType.UserObjectId)
            .Add(p => p.MappedRoles, new List<ClientMappedRole>())
            .Add(p => p.IsReadonly, false)
            .Add(p => p.OnCreateNew, EventCallback.Factory.Create(this, () => createNewCalled = true))
            .Add(p => p.OnDeleteRoleMapping, EventCallback.Factory.Create<ClientPropertyRoleMappingDtoRead>(this, _ => { }))
        ));

        // Act & Assert
        var createButton = cut.FindAll("button")[0];
        createButton.MarkupMatches("<button diff:ignoreAttributes><span class=\"k-button-text\">Create User Mapping</span></button>");
        createButton.Click();
        Assert.That(createNewCalled, Is.True);
    }

    [Test]
    public void Component_WithMappedRoles_RendersGrid()
    {
        // Arrange
        var mappedRoles = CreateMappedRoles();

        // Act
        var cut = _ctx.RenderComponent<TelerikRootComponent>(parameters => parameters
            .AddChildContent<ClientRoleMapListItem>(childParameters => childParameters
            .Add(p => p.MapType, RoleMapType.UserObjectId)
            .Add(p => p.MappedRoles, mappedRoles)
            .Add(p => p.OnCreateNew, EventCallback.Factory.Create(this, () => { }))
            .Add(p => p.OnDeleteRoleMapping, EventCallback.Factory.Create<ClientPropertyRoleMappingDtoRead>(this, _ => { }))
        ));

        // Assert
        var table = cut.Find(".k-grid-table");
        using (Assert.EnterMultipleScope())
        {
            Assert.That(table.TextContent, Does.Contain(mappedRoles[0].ClientRoleName));
            Assert.That(table.TextContent, Does.Contain(mappedRoles[0].RoleMappingValue));
            Assert.That(table.TextContent, Does.Contain(mappedRoles[0].RoleMappingDescription));
        }
    }

    [Test]
    public void OnInitializedAsync_WithInvalidOperationException_ContinuesWithoutError()
    {
        // Arrange
        _mockStorageService.GetItem<int?>(Arg.Any<string>()).Throws(new InvalidOperationException("Pre-rendering error"));

        // Act & Assert - Should not throw
        var cut = _ctx.RenderComponent<ClientRoleMapListItem>(parameters => parameters
            .Add(p => p.MapType, RoleMapType.UserObjectId)
            .Add(p => p.MappedRoles, new List<ClientMappedRole>())
            .Add(p => p.OnCreateNew, EventCallback.Factory.Create(this, () => { }))
            .Add(p => p.OnDeleteRoleMapping, EventCallback.Factory.Create<ClientPropertyRoleMappingDtoRead>(this, _ => { }))
        );

        Assert.That(cut.Markup, Does.Contain("User Role Mapping"));
    }

    [Test]
    public void Component_WhenNoMappedRoles_RendersNoDataMessage()
    {
        // Act
        var cut = _ctx.RenderComponent<TelerikRootComponent>(parameters => parameters
            .AddChildContent<ClientRoleMapListItem>(childParameters => childParameters
            .Add(p => p.MapType, RoleMapType.UserObjectId)
            .Add(p => p.MappedRoles, new List<ClientMappedRole>())
            .Add(p => p.OnCreateNew, EventCallback.Factory.Create(this, () => { }))
            .Add(p => p.OnDeleteRoleMapping, EventCallback.Factory.Create<ClientPropertyRoleMappingDtoRead>(this, _ => { }))
        ));

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(cut.FindAll("table"), Is.Empty);
            var lastDiv = cut.Find(".card-body");
            lastDiv.MarkupMatches("<div class=\"card-body\"><span class=\"form-text\">None</span></div>");
        }
    }

    [Test]
    public void Component_WhenDeleteButtonClicked_InvokesOnDeleteRoleMapping()
    {
        // Arrange
        ClientPropertyRoleMappingDtoRead deletedMapping = null;
        var mappedRoles = CreateMappedRoles();

        var cut = _ctx.RenderComponent<TelerikRootComponent>(parameters => parameters
            .AddChildContent<ClientRoleMapListItem>(childParameters => childParameters
            .Add(p => p.MapType, RoleMapType.UserObjectId)
            .Add(p => p.MappedRoles, mappedRoles)
            .Add(p => p.OnCreateNew, EventCallback.Factory.Create(this, () => { }))
            .Add(p => p.OnDeleteRoleMapping, EventCallback.Factory.Create<ClientPropertyRoleMappingDtoRead>(this, mapping => deletedMapping = mapping))
        ));

        // Act
        var deleteButton = cut.Find("button.k-button-outline-error");
        deleteButton.Click();

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(deletedMapping, Is.Not.Null);
            Assert.That(deletedMapping.Value, Is.EqualTo(mappedRoles[0].RoleMappingValue));
        }
    }

    private static void SetupCommonInterop(TestContext ctx)
    {
        ctx.JSInterop.SetupVoid("TelerikBlazor.setOptions", _ => true);
        ctx.JSInterop.SetupVoid("TelerikBlazor.initFilterMenu", _ => true);
        ctx.JSInterop.SetupVoid("TelerikBlazor.Grid.initializeGrid", _ => true);
        ctx.JSInterop.SetupVoid("TelerikBlazor.Grid.initializeGrouping", _ => true);
        ctx.JSInterop.SetupVoid("TelerikBlazor.Grid.initializeSorting", _ => true);
        ctx.JSInterop.SetupVoid("TelerikBlazor.Grid.initializeFiltering", _ => true);
        ctx.JSInterop.SetupVoid("TelerikBlazor.Grid.initializePaging", _ => true);
        ctx.JSInterop.SetupVoid("TelerikBlazor.ToolBar.initializeToolBar", _ => true);
        ctx.JSInterop.Setup<string>("TelerikBlazor.getTimezoneOffset", _ => true).SetResult("0");
        ctx.JSInterop.Setup<string>("TelerikBlazor.getTimezone", _ => true).SetResult("UTC");
        ctx.JSInterop.SetupVoid("TelerikBlazor.initColumnResizable", _ => true);

        ctx.JSInterop.SetupVoid("TelerikBlazor.Grid.expandHierarchy", _ => true);
        ctx.JSInterop.SetupVoid("TelerikBlazor.Grid.collapseHierarchy", _ => true);
        ctx.JSInterop.SetupVoid("TelerikBlazor.Pager.setPage", _ => true);
        ctx.JSInterop.SetupVoid("TelerikBlazor.Pager.setPageSize", _ => true);
        ctx.JSInterop.Setup<object>("TelerikBlazor.getElementBounds", _ => true).SetResult(new { width = 100, height = 100 });
    }

    private static List<ClientMappedRole> CreateMappedRoles(RoleMapType mapType = RoleMapType.UserObjectId)
    {
        ClientRoleMapType clientMapType = (ClientRoleMapType)(int)mapType;
        return new List<ClientMappedRole>
        {
            new()
            {
                ClientRoleName = "Test Client Role",
                RoleMapping = new ClientPropertyRoleMappingDtoRead
                {
                    Value = "Test Client Mapping Value",
                    Description = "Test Client Display Name",
                    MappingType = clientMapType
                }
            }
        };
    }
}
