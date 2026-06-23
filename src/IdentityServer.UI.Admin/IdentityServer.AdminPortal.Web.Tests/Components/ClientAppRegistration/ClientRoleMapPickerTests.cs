// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

using Bunit;
using Microsoft.AspNetCore.Components;
using Microsoft.Extensions.DependencyInjection;
using NSubstitute;
using IdentityServer.Abstraction.DTO.Clients;
using IdentityServer.Abstraction.Entities.IdentityServerConfig;
using IdentityServer.AdminPortal.Web.Components.ClientAppRegistration;
using IdentityServer.AdminPortal.Web.Components.Primitive.List;
using IdentityServer.AdminPortal.Web.Services.Search;
using IdentityServer.Tests.Common.Builders;
using Group = IdentityServer.Abstraction.Entities.EntraEntities.Group;
using TestContext = Bunit.TestContext;
using User = IdentityServer.Abstraction.Entities.EntraEntities.User;

namespace IdentityServer.AdminPortal.Web.Tests.Components.ClientAppRegistration;

[TestFixture]
public class ClientRoleMapPickerTests
{
    private TestContext _ctx;
    private ISearchProvider<Group> _mockGroupSearchProvider;
    private ISearchProvider<User> _mockUserSearchProvider;
    private List<ClientPropertyRoleDtoRead> _testRoles;

    [SetUp]
    public void Setup()
    {
        _ctx = new TestContext();
        _mockGroupSearchProvider = Substitute.For<ISearchProvider<Group>>();
        _mockUserSearchProvider = Substitute.For<ISearchProvider<User>>();
        _testRoles = CreateTestRoles();

        _ctx.Services.AddSingleton(_mockGroupSearchProvider);
        _ctx.Services.AddSingleton(_mockUserSearchProvider);

        SetupTelerikInterop();
    }

    [TearDown]
    public void TearDown()
    {
        _ctx?.Dispose();
    }

    [Test]
    public void Render_WhenClosed_DoesNotRenderOffcanvas()
    {
        // Arrange & Act
        var cut = _ctx.RenderComponent<ClientRoleMapPicker>(parameters => parameters
            .Add(p => p.ExistingRoles, _testRoles));

        // Assert
        Assert.That(cut.FindAll(".offcanvas"), Has.Count.EqualTo(0));
    }

    [TestCase(ClientRoleMapType.SecurityGroup, "Security Group")]
    [TestCase(ClientRoleMapType.UserObjectId, "User")]
    public async Task OpenRoleMappingPicker_RendersOffcanvasWithCorrectTitle(ClientRoleMapType roleMapType, string friendlyName)
    {
        // Arrange
        var roleMapping = new ClientRoleMappingDtoCreateBuilder(roleMapType).Build();
        var cut = _ctx.RenderComponent<ClientRoleMapPicker>(parameters => parameters
            .Add(p => p.ExistingRoles, _testRoles));

        // Act
        await cut.InvokeAsync(() => cut.Instance.OpenRoleMappingPicker(roleMapping));

        // Assert
        var title = cut.Find("#applicationRoleMapEditorTitle");
        Assert.That(title.TextContent, Is.EqualTo($"New {friendlyName} Role Mapping"));
    }

    [Test]
    public async Task OpenRoleMappingPicker_WhenOpened_ShowsRoleSelection()
    {
        var roleMapping = new ClientRoleMappingDtoCreateBuilder(ClientRoleMapType.SecurityGroup).Build();
        var cut = _ctx.RenderComponent<ClientRoleMapPicker>(parameters => parameters
            .Add(p => p.ExistingRoles, _testRoles));

        // Act
        await cut.InvokeAsync(() => cut.Instance.OpenRoleMappingPicker(roleMapping));

        // Assert
        var roleButtons = cut.FindAll("table tbody tr span.btn-link");

        using (Assert.EnterMultipleScope())
        {
            Assert.That(roleButtons, Has.Count.EqualTo(2));
            Assert.That(roleButtons[0].TextContent, Is.EqualTo("TestRole1"));
            Assert.That(roleButtons[1].TextContent, Is.EqualTo("TestRole2"));
        }
    }

    [Test]
    public async Task CloseEditorDrawer_WhenCalled_HidesOffcanvas()
    {
        // Arrange
        var roleMapping = new ClientRoleMappingDtoCreateBuilder(ClientRoleMapType.SecurityGroup).Build();
        var cut = _ctx.RenderComponent<ClientRoleMapPicker>(parameters => parameters
            .Add(p => p.ExistingRoles, _testRoles));
        await cut.InvokeAsync(() => cut.Instance.OpenRoleMappingPicker(roleMapping));

        // Act
        var closeButton = cut.Find("button.btn-close");
        await cut.InvokeAsync(() => closeButton.Click());

        // Assert
        Assert.That(cut.FindAll(".offcanvas"), Has.Count.EqualTo(0));
    }

    [Test]
    public async Task SetSelectedRole_WhenClicked_ShowsRoleHeader()
    {
        // Arrange
        var roleMapping = new ClientRoleMappingDtoCreateBuilder(ClientRoleMapType.SecurityGroup).Build();
        var cut = _ctx.RenderComponent<ClientRoleMapPicker>(parameters => parameters
            .Add(p => p.ExistingRoles, _testRoles));
        await cut.InvokeAsync(() => cut.Instance.OpenRoleMappingPicker(roleMapping));

        // Act
        await SelectFirstVisibleRoleButtonAsync(cut);

        // Assert
        var roleHeader = cut.Find(".offcanvas-header h6");
        Assert.That(roleHeader.TextContent, Does.Contain("Role: TestRole1"));
    }

    [Test]
    public async Task SetSelectedRole_WithSecurityGroupMapping_ShowsGroupSearchPickList()
    {
        // Arrange
        var roleMapping = new ClientRoleMappingDtoCreateBuilder(ClientRoleMapType.SecurityGroup).Build();
        var cut = _ctx.RenderComponent<ClientRoleMapPicker>(parameters => parameters
            .Add(p => p.ExistingRoles, _testRoles));
        await cut.InvokeAsync(() => cut.Instance.OpenRoleMappingPicker(roleMapping));

        // Act
        await SelectFirstVisibleRoleButtonAsync(cut);

        // Assert
        var searchPickList = cut.FindComponent<SearchPickList<string, Group>>();
        Assert.That(searchPickList, Is.Not.Null);
    }

    [Test]
    public async Task SetSelectedRole_WithUserObjectIdMapping_ShowsUserSearchPickList()
    {
        // Arrange
        var roleMapping = new ClientRoleMappingDtoCreateBuilder(ClientRoleMapType.UserObjectId).Build();
        var cut = _ctx.RenderComponent<ClientRoleMapPicker>(parameters => parameters
            .Add(p => p.ExistingRoles, _testRoles));
        await cut.InvokeAsync(() => cut.Instance.OpenRoleMappingPicker(roleMapping));

        // Act
        await SelectFirstVisibleRoleButtonAsync(cut);

        // Assert
        var searchPickList = cut.FindComponent<SearchPickList<string, User>>();
        Assert.That(searchPickList, Is.Not.Null);
    }

    [Test]
    public async Task SetSelectedEntraGroup_WhenClicked_InvokesOnRoleMappingConfirmedCallbackAndClosesDrawer()
    {
        // Arrange
        var callbackInvoked = false;
        ClientPropertyRoleMappingDtoCreate capturedRoleMapping = null;

        var roleMapping = new ClientRoleMappingDtoCreateBuilder(ClientRoleMapType.SecurityGroup).Build();

        var cut = _ctx.RenderComponent<ClientRoleMapPicker>(parameters => parameters
            .Add(p => p.ExistingRoles, _testRoles)
            .Add(p => p.OnRoleMappingConfirmed, EventCallback.Factory.Create<ClientPropertyRoleMappingDtoCreate>(this, mapping =>
            {
                callbackInvoked = true;
                capturedRoleMapping = mapping;
                return Task.CompletedTask;
            })));

        await cut.InvokeAsync(() => cut.Instance.OpenRoleMappingPicker(roleMapping));

        await SelectFirstVisibleRoleButtonAsync(cut);

        var testGroup = new Group { Id = "test-group-id", DisplayName = "Test Group" };

        // Act
        await cut.InvokeAsync(() => cut.Instance.SetSelectedEntraGroup(testGroup));

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(callbackInvoked, Is.True);
            Assert.That(capturedRoleMapping, Is.Not.Null);
            Assert.That(capturedRoleMapping.Value, Is.EqualTo("test-group-id"));
            Assert.That(capturedRoleMapping.ClientRoleId, Is.EqualTo(1));
            Assert.That(capturedRoleMapping.MappingType, Is.EqualTo(ClientRoleMapType.SecurityGroup));
            Assert.That(cut.FindAll(".offcanvas"), Has.Count.EqualTo(0));
        }
    }

    [Test]
    public async Task SetSelectedUser_WhenClicked_InvokesOnRoleMappingConfirmedCallbackAndClosesDrawer()
    {
        // Arrange
        var callbackInvoked = false;
        ClientPropertyRoleMappingDtoCreate capturedRoleMapping = null;

        var roleMapping = new ClientRoleMappingDtoCreateBuilder(ClientRoleMapType.UserObjectId).Build();

        var cut = _ctx.RenderComponent<ClientRoleMapPicker>(parameters => parameters
            .Add(p => p.ExistingRoles, _testRoles)
            .Add(p => p.OnRoleMappingConfirmed, EventCallback.Factory.Create<ClientPropertyRoleMappingDtoCreate>(this, mapping =>
            {
                callbackInvoked = true;
                capturedRoleMapping = mapping;
                return Task.CompletedTask;
            })));

        await cut.InvokeAsync(() => cut.Instance.OpenRoleMappingPicker(roleMapping));
        await SelectFirstVisibleRoleButtonAsync(cut);
        var testUser = new User { OId = "test-user-oid", DisplayName = "Test User" };

        // Act
        await cut.InvokeAsync(() => cut.Instance.SetSelectedUser(testUser));

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(callbackInvoked, Is.True);
            Assert.That(capturedRoleMapping, Is.Not.Null);
            Assert.That(capturedRoleMapping.Value, Is.EqualTo("test-user-oid"));
            Assert.That(capturedRoleMapping.ClientRoleId, Is.EqualTo(1));
            Assert.That(capturedRoleMapping.MappingType, Is.EqualTo(ClientRoleMapType.UserObjectId));
            Assert.That(cut.FindAll(".offcanvas"), Has.Count.EqualTo(0));
        }
    }

    [Test]
    public async Task SetSelectedRole_WithExistingMappings_ExcludesAlreadyAssignedGroups()
    {
        // Arrange
        var rolesWithMappings = CreateTestRolesWithMappings();
        var roleMapping = new ClientRoleMappingDtoCreateBuilder(ClientRoleMapType.SecurityGroup).Build();

        var cut = _ctx.RenderComponent<ClientRoleMapPicker>(parameters => parameters
            .Add(p => p.ExistingRoles, rolesWithMappings));
        await cut.InvokeAsync(() => cut.Instance.OpenRoleMappingPicker(roleMapping));

        // Act
        await SelectFirstVisibleRoleButtonAsync(cut);

        // Assert
        var searchPickList = cut.FindComponent<SearchPickList<string, Group>>();
        var excludeItems = searchPickList.Instance.ExcludeItems;

        using (Assert.EnterMultipleScope())
        {
            Assert.That(excludeItems, Has.Count.EqualTo(1));
            Assert.That(excludeItems.First().Id, Is.EqualTo("existing-group-id"));
        }
    }

    [Test]
    public async Task SetSelectedRole_WithExistingMappings_ExcludesAlreadyAssignedUsers()
    {
        // Arrange
        var rolesWithMappings = CreateTestRolesWithMappings();
        var roleMapping = new ClientRoleMappingDtoCreateBuilder(ClientRoleMapType.UserObjectId).Build();

        var cut = _ctx.RenderComponent<ClientRoleMapPicker>(parameters => parameters
            .Add(p => p.ExistingRoles, rolesWithMappings));
        await cut.InvokeAsync(() => cut.Instance.OpenRoleMappingPicker(roleMapping));

        // Act
        await SelectFirstVisibleRoleButtonAsync(cut);

        // Assert
        var searchPickList = cut.FindComponent<SearchPickList<string, User>>();
        var excludeItems = searchPickList.Instance.ExcludeItems;

        using (Assert.EnterMultipleScope())
        {
            Assert.That(excludeItems, Has.Count.EqualTo(1));
            Assert.That(excludeItems.First().OId, Is.EqualTo("existing-user-oid"));
        }
    }

    private static async Task SelectFirstVisibleRoleButtonAsync(IRenderedComponent<ClientRoleMapPicker> cut)
    {
        var firstRoleButton = cut.Find("table tbody tr span.btn-link");
        Assert.That(firstRoleButton.TextContent, Is.EqualTo("TestRole1"));
        await cut.InvokeAsync(() => firstRoleButton.Click());
    }

    private static List<ClientPropertyRoleDtoRead> CreateTestRoles()
    {
        return new List<ClientPropertyRoleDtoRead>
        {
            new()
            {
                Id = 1,
                ClientId = 100,
                RoleName = "TestRole1",
                Mappings = new List<ClientPropertyRoleMappingDtoRead>()
            },
            new()
            {
                Id = 2,
                ClientId = 100,
                RoleName = "TestRole2",
                Mappings = new List<ClientPropertyRoleMappingDtoRead>()
            }
        };
    }

    private static List<ClientPropertyRoleDtoRead> CreateTestRolesWithMappings()
    {
        return new List<ClientPropertyRoleDtoRead>
        {
            new()
            {
                Id = 1,
                ClientId = 100,
                RoleName = "TestRole1",
                Mappings = new List<ClientPropertyRoleMappingDtoRead>
                {
                    new()
                    {
                        Id = 1,
                        ClientRoleId = 1,
                        MappingType = ClientRoleMapType.SecurityGroup,
                        Value = "existing-group-id"
                    },
                    new()
                    {
                        Id = 2,
                        ClientRoleId = 1,
                        MappingType = ClientRoleMapType.UserObjectId,
                        Value = "existing-user-oid"
                    }
                }
            }
        };
    }

    private void SetupTelerikInterop()
    {
        // Setup common Telerik interop calls
        _ctx.JSInterop.SetupVoid("TelerikBlazor.getViewPort", _ => true);
        _ctx.JSInterop.SetupVoid("TelerikBlazor.preventScroll", _ => true);
        _ctx.JSInterop.SetupVoid("TelerikBlazor.restoreScroll", _ => true);
        _ctx.JSInterop.Setup<object>("TelerikBlazor.getElementBounds", _ => true)
               .SetResult(new { width = 100, height = 100 });
    }
}
