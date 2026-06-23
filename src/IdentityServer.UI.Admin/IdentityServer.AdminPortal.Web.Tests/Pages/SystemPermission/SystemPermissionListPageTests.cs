// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

using Bunit;
using Microsoft.AspNetCore.Components.Authorization;
using Microsoft.Extensions.DependencyInjection;
using NSubstitute;
using Telerik.Blazor.Components;
using Telerik.DataSource;
using IdentityServer.AdminPortal.Web.Models;
using IdentityServer.AdminPortal.Web.Pages.SystemPermission;
using IdentityServer.AdminPortal.Web.Services;
using IdentityServer.AdminPortal.Web.Services.Storage;
using IdentityServer.Abstraction.DTO.SystemPermissions;
using IdentityServer.Abstraction.Entities.IdentityServerConfig.SystemPermissions;
using IdentityServer.Tests.Common;
using TestContext = Bunit.TestContext;

namespace IdentityServer.AdminPortal.Web.Tests.Pages.SystemPermission;

public class SystemPermissionListPageTests
{
    private IAdminApiService _mockAdminApiService;
    private ISystemOwnerService _systemOwnerService;
    private TestContext _ctx;
    private IJSStorageService _mockStorageService;

    [SetUp]
    public void Setup()
    {
        _ctx = new TestContext();
        SetupCommonInterop(_ctx);
        _mockStorageService = Substitute.For<IJSStorageService>();
        _mockAdminApiService = Substitute.For<IAdminApiService>();
        _systemOwnerService = Substitute.For<ISystemOwnerService>();
        _ctx.Services.AddSingleton(_mockStorageService);
        _ctx.Services.AddSingleton(_mockAdminApiService);
        _ctx.Services.AddSingleton(_systemOwnerService);
        _ctx.Services.AddTelerikBlazor();
    }

    [TearDown]
    public void TearDown()
    {
        _ctx.Dispose();
    }

    [Test]
    public void SystemPermissionListPage_WithGivenParameters_RendersGrid()
    {
        // Arrange
        SetupAuthentication(false);

        var systemPermissions = new List<SystemPermissionShortDtoRead>
        {
            new() { Id = 1, Name = "Permission1", Description = "Test Permission" }
        };
        var dataEnvelope = new DataEnvelope<SystemPermissionShortDtoRead>() { CurrentPageData = systemPermissions, TotalItemCount = systemPermissions.Count };
        var apiCallResult = new ApiCallResult<DataEnvelope<SystemPermissionShortDtoRead>>(dataEnvelope);

        _mockAdminApiService
            .GetSystemPermissionsPaged(Arg.Any<DataSourceRequest>())
            .Returns(Task.FromResult(apiCallResult));

        // Act
        var cut = _ctx.RenderComponent<TelerikRootComponent>(parameters => parameters
            .AddChildContent<SystemPermissionListPage>()
        );

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(cut.Markup, Does.Contain("Permission1"));
            Assert.That(cut.Markup, Does.Contain("Show only My System Permissions"));
        }
    }

    [Test]
    public void SystemPermissionListPage_WithAdmin_DoesnotRenderMySystemPermissionsSwitch()
    {
        // Arrange
        SetupAuthentication(true);

        var systemPermissions = new List<SystemPermissionShortDtoRead>
        {
            new() { Id = 1, Name = "Permission1", Description = "Test Permission" }
        };
        var dataEnvelope = new DataEnvelope<SystemPermissionShortDtoRead>() { CurrentPageData = systemPermissions, TotalItemCount = systemPermissions.Count };
        var apiCallResult = new ApiCallResult<DataEnvelope<SystemPermissionShortDtoRead>>(dataEnvelope);

        _mockAdminApiService
            .GetSystemPermissionsPaged(Arg.Any<DataSourceRequest>())
            .Returns(Task.FromResult(apiCallResult));

        // Act
        var cut = _ctx.RenderComponent<TelerikRootComponent>(parameters => parameters
            .AddChildContent<SystemPermissionListPage>()
        );

        // Assert
        var anySwitches = cut.FindComponents<TelerikSwitch<bool>>();
        using (Assert.EnterMultipleScope())
        {
            Assert.That(anySwitches, Is.Empty, "Expected no toggle switch for admin user");
            Assert.That(cut.Markup, Does.Not.Contain("Show only My System Permissions"));
        }
    }

    [Test]
    public async Task SystemPermissionListPage_OnShowMyItemsToggleChanged_AppliesAccessLevelFilter()
    {
        // Arrange
        SetupAuthentication(isAdmin: false);

        var systemPermissions = new List<SystemPermissionShortDtoRead>
        {
            new() { Id = 1, Name = "Permission1", Description = "Test Permission", AccessLevel = SystemPermissionRoleType.None }
        };
        var dataEnvelope = new DataEnvelope<SystemPermissionShortDtoRead>() { CurrentPageData = systemPermissions, TotalItemCount = systemPermissions.Count };
        var apiCallResult = new ApiCallResult<DataEnvelope<SystemPermissionShortDtoRead>>(dataEnvelope);

        int callCount = 0;
        DataSourceRequest capturedRequest1 = null;
        DataSourceRequest capturedRequest2 = null;
        _mockAdminApiService
            .GetSystemPermissionsPaged(Arg.Any<DataSourceRequest>())
            .Returns(callInfo =>
            {
                if (callCount == 0)
                {
                    capturedRequest1 = callInfo.ArgAt<DataSourceRequest>(0);
                }
                else
                {
                    capturedRequest2 = callInfo.ArgAt<DataSourceRequest>(0);
                }
                callCount++;
                return Task.FromResult(apiCallResult);
            });

        var cut = _ctx.RenderComponent<TelerikRootComponent>(parameters => parameters
            .AddChildContent<SystemPermissionListPage>()
        );

        // Act : Trigger the ValueChanged callback directly
        var toggleSwitch = cut.FindComponent<TelerikSwitch<bool>>();
        await cut.InvokeAsync(async () =>
        {
            await toggleSwitch.Instance.ValueChanged.InvokeAsync(true);
        });

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(callCount, Is.EqualTo(2), "Expected two data requests to be made");
            Assert.That(capturedRequest1, Is.Not.Null, "Expected initial data request to be captured");
            var accessLevelFilter1 = capturedRequest1!.Filters
                .OfType<FilterDescriptor>()
                .FirstOrDefault(f => f.Member == "AccessLevel");
            Assert.That(accessLevelFilter1, Is.Null, "Expected no AccessLevel filter on initial load for non-admin");

            Assert.That(capturedRequest2, Is.Not.Null, "Expected data request to be captured after toggle");
            var accessLevelFilter2 = capturedRequest2!.Filters
                .OfType<FilterDescriptor>()
                .FirstOrDefault(f => f.Member == "AccessLevel");
            Assert.That(accessLevelFilter2, Is.Not.Null, "Expected AccessLevel filter to be added");
            Assert.That(accessLevelFilter2!.Operator, Is.EqualTo(FilterOperator.IsNotEqualTo));
            Assert.That(accessLevelFilter2.Value, Is.EqualTo(SystemPermissionRoleType.None));
        }
    }

    private void SetupAuthentication(bool isAdmin = true)
    {
        var authState = new AuthenticationState(isAdmin ? TestUser.Admin : TestUser.Contributor);
        var mockAuthStateProvider = Substitute.For<AuthenticationStateProvider>();
        mockAuthStateProvider.GetAuthenticationStateAsync().Returns(Task.FromResult(authState));
        _ctx.Services.AddSingleton(mockAuthStateProvider);
    }

    private static void SetupCommonInterop(TestContext ctx)
    {
        ctx.JSInterop.SetupVoid("TelerikBlazor.initFilterRow", _ => true);
        ctx.JSInterop.SetupVoid("TelerikBlazor.initComponentLoaderContainer", _ => true);
        ctx.JSInterop.SetupVoid("TelerikBlazor.initColumnResizable", _ => true);
    }
}
